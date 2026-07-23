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
final class ClipboardSync {
    /// Fast enough to feel instant against the 300 ms p95 target, slow enough to be free.
    private static let pollInterval: TimeInterval = 0.3

    private let pasteboard = NSPasteboard.general
    private let transport: LanTransport

    private var guard_: LoopGuard?
    private var watcher: Task<Void, Never>?
    private var lastChangeCount: Int

    init(transport: LanTransport) {
        self.transport = transport
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start(selfDeviceId: String) {
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

    func stop() {
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

        guard
            var loopGuard = guard_,
            let text = pasteboard.string(forType: .string),
            !text.isEmpty
        else { return }

        let allowed = loopGuard.shouldEmit(contentHash: LoopGuard.hash(text))
        guard_ = loopGuard // shouldEmit consumes the one-shot suppression
        guard allowed else { return }

        var envelope = transport.newEnvelope()
        envelope.clipText = FuseClipText.with { $0.text = text }
        transport.broadcast(envelope)
    }

    private func apply(_ envelope: FuseEnvelope) {
        guard case .clipText = envelope.body else { return }
        let text = envelope.clipText.text
        guard !text.isEmpty, var loopGuard = guard_ else { return }

        let allowed = loopGuard.shouldApply(
            sourceDeviceId: envelope.sourceDeviceID,
            seq: envelope.seq,
            sentAtUnixMs: envelope.sentAtUnixMs,
        )
        guard allowed else {
            guard_ = loopGuard
            return
        }
        loopGuard.recordApplied(
            contentHash: LoopGuard.hash(text), sentAtUnixMs: envelope.sentAtUnixMs,
        )
        guard_ = loopGuard

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Writing bumps changeCount; absorb it here so the next poll does not treat our
        // own injection as a user copy. The hash suppression in LoopGuard covers the
        // same case, but not paying for a wasted comparison is free.
        lastChangeCount = pasteboard.changeCount
    }
}
