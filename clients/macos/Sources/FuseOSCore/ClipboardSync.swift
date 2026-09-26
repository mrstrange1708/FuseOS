import AppKit
import Foundation

/// One entry in the visible clipboard history. `imageData` is nil for text and the raw
/// encoded image otherwise — the same bytes that crossed the wire, so re-copying an old
/// item needs no re-encode. Mirrors `ClipEntry` on Android.
public struct ClipEntry: Identifiable, Equatable {
    public let id: Int
    public let text: String?
    public let imageData: Data?
    public let mime: String?
    /// True when this device copied it, false when it arrived from a peer.
    public let fromSelf: Bool
    public let at: Date

    public var isImage: Bool { imageData != nil }

    public init(id: Int, text: String?, imageData: Data?, mime: String?, fromSelf: Bool, at: Date) {
        self.id = id
        self.text = text
        self.imageData = imageData
        self.mime = mime
        self.fromSelf = fromSelf
        self.at = at
    }

    public static func == (a: ClipEntry, b: ClipEntry) -> Bool { a.id == b.id }
}

/// A local copy that has not been sent yet. Calling `send` records and broadcasts it.
public struct ClipOffer {
    public let text: String?
    public let imageData: Data?
    public let send: () -> Void
}

/// Mirrors the clipboard to paired devices over the LAN data plane.
///
/// **`NSPasteboard` has no change notification.** There is no observer, no delegate, no
/// notification — the only way to detect a copy is to watch `changeCount`. That is why
/// this polls, and it is the one place the project's no-polling rule does not apply: the
/// rule is about network round trips, and this is a local integer read on a timer with no
/// I/O behind it. See `docs/protocol.md`.
///
/// All loop-prevention lives in `LoopGuard`; this class only bridges it to the platform.
@MainActor
public final class ClipboardSync {
    /// Fast enough to feel instant against the 300 ms p95 target, slow enough to be free.
    private static let pollInterval: TimeInterval = 0.3

    private let pasteboard: NSPasteboard
    private let transport: LanTransport

    private var guard_: LoopGuard?
    private var watcher: Task<Void, Never>?
    private var lastChangeCount: Int

    /// Newest first. In memory only — clipboard content is never written to disk here.
    public private(set) var history: [ClipEntry] = []

    /// Fires whenever `history` changes, so the dashboard can republish it. A callback
    /// rather than `@Published` keeps this type free of Combine, matching `LanTransport`.
    public var onHistoryChanged: (([ClipEntry]) -> Void)?

    /// Fires once per clip as it happens, in either direction — what the island animates.
    /// Separate from `onHistoryChanged` because that also fires on eviction and on
    /// sign-out clearing, neither of which is an event worth showing anyone.
    public var onClipEvent: ((ClipEntry) -> Void)?

    /// Each clip's round trip as it is acknowledged (see `SyncLatency`).
    public var onLatency: ((SyncLatency) -> Void)?
    private var latency = LatencyWindow()
    /// Clips sent and not yet acknowledged: seq → when they went, monotonic nanoseconds.
    private var awaitingAck: [UInt64: UInt64] = [:]

    /// Set, and a local copy is offered instead of sent: the handler decides, and calls
    /// `send` if the user says yes. Unset — the default — every copy goes at once, because
    /// latency is the product and a prompt is a click in front of every sync.
    public var onLocalCopy: ((ClipOffer) -> Void)?

    private var nextId = 0
    private let store = ClipHistoryStore()

    /// The pasteboard is injectable so tests can drive a private one — exercising this
    /// against `NSPasteboard.general` would fight whoever is using the machine.
    public init(transport: LanTransport, pasteboard: NSPasteboard = .general) {
        self.transport = transport
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    public func start(selfDeviceId: String) {
        stop()
        guard_ = LoopGuard(selfDeviceId: selfDeviceId)
        // Restored ids continue upward rather than restarting, so a reloaded entry and a
        // fresh one can never collide in a list keyed by id.
        history = store.load()
        nextId = (history.map(\.id).max() ?? -1) + 1
        onHistoryChanged?(history)
        // Start from the current count so an item copied before launch is not
        // broadcast as if the user just copied it.
        lastChangeCount = pasteboard.changeCount

        transport.onEnvelope = { [weak self] envelope in
            self?.apply(envelope)
        }
        FuseLog.clipboard.info("clipboard sync started as \(selfDeviceId, privacy: .public)")

        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                self?.checkForLocalChange()
            }
        }
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        transport.onEnvelope = nil
        guard_ = nil
        // Only clears memory; what is on disk is what the next launch restores.
        // `forget()` is the sign-out path.
        history = []
        onHistoryChanged?(history)
    }

    /// Sign-out: drop the history from memory *and* disk.
    public func forget() {
        stop()
        store.clear()
    }

    /// Adds to the visible history, newest first, and evicts to keep it bounded.
    ///
    /// Two caps, because entries are wildly uneven: `maxEntries` keeps the list readable,
    /// and `maxHistoryBytes` keeps 50 screenshots from pinning 150 MB of memory.
    private func record(text: String?, imageData: Data?, mime: String?, fromSelf: Bool) {
        let entry = ClipEntry(
            id: nextId, text: text, imageData: imageData, mime: mime,
            fromSelf: fromSelf, at: Date(),
        )
        nextId += 1
        onClipEvent?(entry)
        commit([entry] + history)
    }

    /// Trims a new history to the caps, publishes it, and persists it.
    private func commit(_ entries: [ClipEntry]) {
        var bytes = 0
        let trimmed = entries.prefix(Self.maxEntries).prefix {
            bytes += $0.imageData?.count ?? $0.text?.count ?? 0
            return bytes <= Self.maxHistoryBytes
        }
        history = Array(trimmed)
        onHistoryChanged?(history)
        // Written on every change so a crash or a force-quit does not lose the history.
        // Off the main actor: a screenshot is megabytes, and the pasteboard watcher must
        // not wait on a disk write.
        let snapshot = history
        let store = store
        Task.detached(priority: .utility) { store.save(snapshot) }
    }

    /// Sends our recent history to peers that just connected (`HistorySync` in the proto),
    /// newest first, stopping short of the channel's frame cap. Images too big for what is
    /// left of the budget are skipped rather than ending the list.
    public func sendHistory() {
        var budget = Self.maxHistorySyncBytes
        var sync = FuseHistorySync()
        for entry in history {
            let size = entry.imageData?.count ?? entry.text?.utf8.count ?? 0
            guard size <= budget else { continue }
            budget -= size
            sync.items.append(FuseHistoryItem.with {
                if let data = entry.imageData {
                    $0.imageData = data
                    $0.imageMime = entry.mime ?? "image/png"
                } else {
                    $0.text = entry.text ?? ""
                }
                $0.atUnixMs = Int64(entry.at.timeIntervalSince1970 * 1000)
            })
        }
        guard !sync.items.isEmpty else { return }
        var envelope = transport.newEnvelope()
        envelope.historySync = sync
        transport.broadcast(envelope)
    }

    /// Folds a peer's history into ours: the entries we lack, at the time they were first
    /// copied. History only — the clipboard is not touched, the island stays quiet, and
    /// nothing is sent back, which is what keeps this from looping.
    func merge(_ sync: FuseHistorySync) {
        var known = Set(history.compactMap(Self.contentHash))
        var added: [ClipEntry] = []
        for item in sync.items {
            let isImage = !item.imageData.isEmpty
            guard isImage || !item.text.isEmpty else { continue }
            let hash = isImage ? LoopGuard.hash(item.imageData) : LoopGuard.hash(item.text)
            guard known.insert(hash).inserted else { continue }
            added.append(ClipEntry(
                id: nextId,
                text: isImage ? nil : item.text,
                imageData: isImage ? item.imageData : nil,
                mime: isImage ? item.imageMime : nil,
                fromSelf: false,
                at: Date(timeIntervalSince1970: Double(item.atUnixMs) / 1000),
            ))
            nextId += 1
        }
        guard !added.isEmpty else { return }
        commit((history + added).sorted { $0.at > $1.at })
    }

    private static func contentHash(_ entry: ClipEntry) -> String? {
        if let data = entry.imageData { return LoopGuard.hash(data) }
        return entry.text.map { LoopGuard.hash($0) }
    }

    /// Put a history entry back on this device's clipboard — the point of a history.
    public func copyToClipboard(_ entry: ClipEntry) {
        // Goes through the same guard as an inbound apply, so re-copying an old item
        // isn't mistaken for a fresh local copy and rebroadcast to the peer.
        let hash: String
        if let data = entry.imageData {
            hash = LoopGuard.hash(data)
        } else if let text = entry.text {
            hash = LoopGuard.hash(text)
        } else {
            return
        }
        if var loopGuard = guard_ {
            loopGuard.recordApplied(contentHash: hash, sentAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
            guard_ = loopGuard
        }

        pasteboard.clearContents()
        if let data = entry.imageData {
            pasteboard.setData(data, forType: Self.pasteboardType(for: entry.mime ?? "image/png"))
        } else if let text = entry.text {
            pasteboard.setString(text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    /// A local copy — broadcast it unless it is the echo of something we just injected.
    ///
    /// Internal rather than private so tests can step the poll deterministically instead
    /// of sleeping through the 300 ms timer.
    func checkForLocalChange() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard var loopGuard = guard_ else {
            FuseLog.clipboard.warning("inbound clip dropped: sync not started")
            return
        }

        // Images first: a copied image often also carries a text representation (a file
        // path), and syncing that instead of the picture would be the wrong choice.
        var body: (FuseEnvelope) -> FuseEnvelope
        var hash: String
        var entry: (text: String?, image: Data?, mime: String?)
        if let (mime, data) = currentImage() {
            guard data.count <= Self.maxInlineImageBytes else { return }
            hash = LoopGuard.hash(data)
            entry = (nil, data, mime)
            body = { envelope in
                var copy = envelope
                copy.clipImage = FuseClipImage.with {
                    $0.mime = mime
                    $0.data = data
                }
                return copy
            }
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            hash = LoopGuard.hash(text)
            entry = (text, nil, nil)
            body = { envelope in
                var copy = envelope
                copy.clipText = FuseClipText.with { $0.text = text }
                return copy
            }
        } else {
            return
        }

        let allowed = loopGuard.shouldEmit(contentHash: hash)
        guard_ = loopGuard // shouldEmit consumes the one-shot suppression
        guard allowed else { return }

        let send = { [weak self] in
            guard let self else { return }
            self.record(text: entry.text, imageData: entry.image, mime: entry.mime, fromSelf: true)
            let envelope = body(self.transport.newEnvelope())
            self.awaitingAck[envelope.seq] = DispatchTime.now().uptimeNanoseconds
            // Bounded: a peer that never acks (an older build) must not grow this forever.
            if self.awaitingAck.count > 64, let oldest = self.awaitingAck.keys.min() {
                self.awaitingAck.removeValue(forKey: oldest)
            }
            self.transport.broadcast(envelope)
        }
        if let offer = onLocalCopy {
            offer(ClipOffer(text: entry.text, imageData: entry.image, send: send))
        } else {
            send()
        }
    }

    func apply(_ envelope: FuseEnvelope) {
        // Resolve the payload and its identity before touching the guard, so text and
        // images go through exactly the same loop-prevention path.
        let write: () -> Void
        let hash: String
        let entry: (text: String?, image: Data?, mime: String?)
        switch envelope.body {
        case .historySync(let sync):
            merge(sync)
            return
        case .ack(let ack):
            guard let sentAt = awaitingAck.removeValue(forKey: ack.refSeq) else { return }
            let ms = Int((DispatchTime.now().uptimeNanoseconds - sentAt) / 1_000_000)
            onLatency?(latency.record(ms))
            return
        case .clipText:
            let text = envelope.clipText.text
            guard !text.isEmpty else { return }
            hash = LoopGuard.hash(text)
            entry = (text, nil, nil)
            write = { [pasteboard] in
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        case .clipImage:
            let image = envelope.clipImage
            guard !image.data.isEmpty else { return }
            hash = LoopGuard.hash(image.data)
            entry = (nil, image.data, image.mime)
            write = { [pasteboard] in
                pasteboard.clearContents()
                pasteboard.setData(image.data, forType: Self.pasteboardType(for: image.mime))
            }
        default:
            return
        }

        guard var loopGuard = guard_ else {
            FuseLog.clipboard.warning("inbound clip dropped: sync not started")
            return
        }
        let allowed = loopGuard.shouldApply(
            sourceDeviceId: envelope.sourceDeviceID,
            sessionId: envelope.sessionID,
            seq: envelope.seq,
            sentAtUnixMs: envelope.sentAtUnixMs,
        )
        guard allowed else {
            FuseLog.clipboard.info(
                "inbound clip refused by loop guard from \(envelope.sourceDeviceID, privacy: .public) seq \(envelope.seq) session \(envelope.sessionID, privacy: .public)",
            )
            guard_ = loopGuard
            return
        }
        loopGuard.recordApplied(contentHash: hash, sentAtUnixMs: envelope.sentAtUnixMs)
        guard_ = loopGuard

        record(text: entry.text, imageData: entry.image, mime: entry.mime, fromSelf: false)
        write()
        // Tell the sender it landed, so it can time the round trip.
        var ack = transport.newEnvelope()
        ack.ack = FuseAck.with { $0.refSeq = envelope.seq }
        transport.broadcast(ack)
        // Deliberately do NOT absorb the bumped changeCount here. Letting the next poll
        // see the change is what delivers the echo to `checkForLocalChange`, where the
        // one-shot hash suppression consumes it. Absorbing it instead leaves that
        // suppression armed indefinitely, so a genuine copy of the same content later —
        // minutes later, by the user — gets silently swallowed. It also keeps this
        // identical to Android, where writing the clipboard fires the change listener.
    }

    /// PNG straight through; TIFF (what a Finder copy usually yields) converted, so the
    /// receiving device never has to know about a Mac-specific format.
    private func currentImage() -> (String, Data)? {
        if let png = pasteboard.data(forType: .png) { return ("image/png", png) }
        guard
            let tiff = pasteboard.data(forType: .tiff),
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return ("image/png", png)
    }

    private static func pasteboardType(for mime: String) -> NSPasteboard.PasteboardType {
        switch mime {
        case "image/tiff": return .tiff
        default: return .png
        }
    }

    /// Images ride inline in a single `ClipImage` frame rather than being chunked. A
    /// screenshot is typically 1–2 MB, one frame on a LAN is faster than a chunked
    /// stream, and `LanChannel` already caps a frame at 4 MB. Anything larger is not
    /// synced today; it will be covered when file transfer brings chunk reassembly.
    private static let maxInlineImageBytes = 3 * 1024 * 1024

    private static let maxEntries = 50
    private static let maxHistoryBytes = 24 * 1024 * 1024
    /// One `HistorySync` frame, with headroom under `LanChannel`'s 4 MB frame cap.
    private static let maxHistorySyncBytes = 3 * 1024 * 1024
}
