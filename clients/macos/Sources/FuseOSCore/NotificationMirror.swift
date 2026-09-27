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
    /// The app offers an inline reply (a chat, an SMS), so the Mac can offer one too.
    public let canReply: Bool
    /// A live activity (timer, route, delivery, download): shown live, never as a banner.
    public let ongoing: Bool
    /// 0–1 when it shows progress, nil when it does not; `indeterminate` for a spinner.
    public let progress: Double?
    public let indeterminate: Bool

    public init(
        id: String, appName: String, title: String, text: String, iconPNG: Data?, postedAt: Date,
        canReply: Bool = false, ongoing: Bool = false, progress: Double? = nil, indeterminate: Bool = false,
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.text = text
        self.iconPNG = iconPNG
        self.postedAt = postedAt
        self.canReply = canReply
        self.ongoing = ongoing
        self.progress = progress
        self.indeterminate = indeterminate
    }
}

/// A phone call, as the phone's dialer notification describes it.
public struct PhoneCall: Equatable {
    public enum State: Equatable { case ringing, active, ended }
    public let key: String
    public let caller: String
    public let state: State
}

/// The Mac end of notification sync (`PhoneNotification` in the proto).
///
/// The phone is the only origin: this shows what arrives and sends back only dismissals
/// the user made here. A dismissal applied here is never re-sent, so nothing can loop.
@MainActor
public final class NotificationMirror {
    public var onPosted: ((PhoneNotification) -> Void)?
    public var onRemoved: ((String) -> Void)?
    public var onCall: ((PhoneCall) -> Void)?

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

    /// Replies through the app's own inline-reply action on the phone.
    public func reply(key: String, text: String) {
        guard !text.isEmpty else { return }
        var envelope = transport.newEnvelope()
        envelope.notificationReply = FuseNotificationReply.with {
            $0.key = key
            $0.text = text
        }
        transport.broadcast(envelope)
    }

    public func answerCall() { callAction(.answer) }
    public func declineCall() { callAction(.decline) }
    public func endCall() { callAction(.end) }

    private func callAction(_ action: FuseCallAction.Action) {
        var envelope = transport.newEnvelope()
        envelope.callAction = FuseCallAction.with { $0.action = action }
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
                canReply: n.canReply,
                ongoing: n.ongoing,
                progress: n.progressMax > 0 ? min(1, Double(n.progress) / Double(n.progressMax)) : nil,
                indeterminate: n.indeterminate,
            ))
        case .callState(let call):
            let state: PhoneCall.State
            switch call.state {
            case .ringing: state = .ringing
            case .active: state = .active
            default: state = .ended
            }
            onCall?(PhoneCall(key: call.key, caller: call.caller, state: state))
        case .notificationDismiss(let d):
            onRemoved?(d.key)
        default:
            break
        }
    }
}
