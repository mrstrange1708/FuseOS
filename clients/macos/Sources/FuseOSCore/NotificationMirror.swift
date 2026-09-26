import Foundation

/// A notification posted on the phone. Plain values, so the app target never touches
/// the generated protobuf types.
public struct PhoneNotification: Identifiable, Equatable {
    /// Android's notification key — stable across updates, so it doubles as the id.
    public let id: String
    public let appName: String
    public let title: String
    public let text: String
    public let iconPNG: Data?
    public let postedAt: Date
}

/// The Mac end of notification sync (`PhoneNotification` in the proto).
///
/// The phone is the only origin: this shows what arrives and sends back only dismissals
/// the user made here. A dismissal applied here is never re-sent, so nothing can loop.
@MainActor
public final class NotificationMirror {
    public var onPosted: ((PhoneNotification) -> Void)?
    public var onRemoved: ((String) -> Void)?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onNotificationEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    /// The user cleared this notification on the Mac; clear it on the phone too.
    public func dismiss(key: String) {
        var envelope = transport.newEnvelope()
        envelope.notificationDismiss = FuseNotificationDismiss.with { $0.key = key }
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case .phoneNotification(let n):
            guard !n.key.isEmpty else { return }
            onPosted?(PhoneNotification(
                id: n.key,
                appName: n.appName,
                title: n.title,
                text: n.text,
                iconPNG: n.iconPng.isEmpty ? nil : n.iconPng,
                postedAt: Date(timeIntervalSince1970: Double(n.postedAtUnixMs) / 1000),
            ))
        case .notificationDismiss(let d):
            onRemoved?(d.key)
        default:
            break
        }
    }
}
