import AppKit
import Foundation

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

    private let pasteboard = NSPasteboard.general
    private let transport: LanTransport

    private var guard_: LoopGuard?
    private var watcher: Task<Void, Never>?
    private var lastChangeCount: Int

    public init(transport: LanTransport) {
        self.transport = transport
        lastChangeCount = NSPasteboard.general.changeCount
    }

    public func start(selfDeviceId: String) {
        stop()
        guard_ = LoopGuard(selfDeviceId: selfDeviceId)
        // Start from the current count so an item copied before launch is not
        // broadcast as if the user just copied it.
        lastChangeCount = pasteboard.changeCount

        transport.onEnvelope = { [weak self] envelope in
            self?.apply(envelope)
        }

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
    }

    /// A local copy — broadcast it unless it is the echo of something we just injected.
    private func checkForLocalChange() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard var loopGuard = guard_ else { return }

        // Images first: a copied image often also carries a text representation (a file
        // path), and syncing that instead of the picture would be the wrong choice.
        var body: (FuseEnvelope) -> FuseEnvelope
        var hash: String
        if let (mime, data) = currentImage() {
            guard data.count <= Self.maxInlineImageBytes else { return }
            hash = LoopGuard.hash(data)
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

        transport.broadcast(body(transport.newEnvelope()))
    }

    private func apply(_ envelope: FuseEnvelope) {
        // Resolve the payload and its identity before touching the guard, so text and
        // images go through exactly the same loop-prevention path.
        let write: () -> Void
        let hash: String
        switch envelope.body {
        case .clipText:
            let text = envelope.clipText.text
            guard !text.isEmpty else { return }
            hash = LoopGuard.hash(text)
            write = { [pasteboard] in
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        case .clipImage:
            let image = envelope.clipImage
            guard !image.data.isEmpty else { return }
            hash = LoopGuard.hash(image.data)
            write = { [pasteboard] in
                pasteboard.clearContents()
                pasteboard.setData(image.data, forType: Self.pasteboardType(for: image.mime))
            }
        default:
            return
        }

        guard var loopGuard = guard_ else { return }
        let allowed = loopGuard.shouldApply(
            sourceDeviceId: envelope.sourceDeviceID,
            seq: envelope.seq,
            sentAtUnixMs: envelope.sentAtUnixMs,
        )
        guard allowed else {
            guard_ = loopGuard
            return
        }
        loopGuard.recordApplied(contentHash: hash, sentAtUnixMs: envelope.sentAtUnixMs)
        guard_ = loopGuard

        write()
        // Writing bumps changeCount; absorb it here so the next poll does not treat our
        // own injection as a user copy. The hash suppression in LoopGuard covers the
        // same case, but not paying for a wasted comparison is free.
        lastChangeCount = pasteboard.changeCount
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
}
