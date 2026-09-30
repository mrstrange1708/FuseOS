import Foundation

/// Product analytics: which features people use and how often — counts, never content
/// (CLAUDE.md principle 6). Every feature crosses `LanChannel.send`, so that one call names it
/// here from the message type; nothing inside a message is read beyond its size. The app
/// points `record` at PostHog (`Analytics` in the app target); left nil — tests, analytics
/// off — nothing is recorded. Mirrors Android's `Usage`.
public enum Usage {
    public struct Feature: Equatable {
        public let name: String
        public let properties: [String: AnyHashable]

        init(_ name: String, _ properties: [String: AnyHashable] = [:]) {
            self.name = name
            self.properties = properties
        }
    }

    public nonisolated(unsafe) static var record: (@Sendable (Feature) -> Void)?

    /// A trackpad session is one use, not ten thousand moves: these count once per window.
    static let sessionWindow: TimeInterval = 10 * 60
    static let continuous: Set<String> = ["trackpad", "notifications", "now_playing", "remote_control"]
    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastCounted: [String: TimeInterval] = [:]

    static func sent(_ envelope: FuseEnvelope) {
        guard let record, let feature = feature(of: envelope),
              shouldCount(feature.name, now: Date().timeIntervalSince1970) else { return }
        record(feature)
    }

    static func shouldCount(_ name: String, now: TimeInterval) -> Bool {
        guard continuous.contains(name) else { return true }
        lock.lock()
        defer { lock.unlock() }
        if let last = lastCounted[name], now - last < sessionWindow { return false }
        lastCounted[name] = now
        return true
    }

    /// The feature a message starts, or nil for plumbing (acks, chunks, frames, status).
    static func feature(of envelope: FuseEnvelope) -> Feature? {
        switch envelope.body {
        case .clipText: Feature("clipboard_text")
        case .clipImage(let image): Feature("clipboard_image", ["sizeBytes": image.data.count])
        case .fileMeta(let meta): Feature("file_transfer", ["sizeBytes": Int(meta.size)])
        case .screenControl(let control) where control.action == .start:
            Feature("screen_mirroring", ["remoteControl": control.remoteControl])
        case .sidecarControl(let control) where control.action == .start: Feature("sidecar")
        case .phoneCommand(let command) where command.action == .ring: Feature("ring_phone")
        case .openLink: Feature("open_link")
        case .mediaCommand: Feature("now_playing")
        case .pointerInput: Feature("trackpad")
        case .remoteInput: Feature("remote_control")
        case .phoneNotification: Feature("notifications")
        case .notificationReply: Feature("notification_reply")
        case .notificationOpen: Feature("notification_open")
        case .callAction(let call): Feature("call", ["action": "\(call.action)"])
        case .unlocked: Feature("unlock")
        default: nil
        }
    }
}
