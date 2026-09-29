import Foundation

/// The Mac's side of `PhoneCommand` and `OpenLink`: ring the phone, hand a link
/// over — and open the links the phone hands back.
@MainActor
public final class PhoneCommands {
    /// A link the phone sent to open here (http/https only; anything else never arrives).
    public var onOpenLink: ((URL) -> Void)?
    /// How something asked of the phone went — a reply, an opened notification.
    public var onOutcome: ((Outcome) -> Void)?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onActionEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    /// Tells the phone how something it asked for went (an unlock, a link it handed over).
    public func sendOutcome(_ kind: Outcome.Kind, ok: Bool, detail: String = "") {
        var envelope = transport.newEnvelope()
        envelope.outcome = FuseOutcome.with {
            $0.kind = kind.wire
            $0.ok = ok
            $0.detail = detail
        }
        transport.broadcast(envelope)
    }

    public func ring() { send(.ring) }
    public func stopRinging() { send(.stopRing) }

    /// Handoff, Mac → phone. False for anything that is not an http(s) link.
    @discardableResult
    public func openOnPhone(_ url: URL) -> Bool {
        guard Self.isWebLink(url) else { return false }
        var envelope = transport.newEnvelope()
        envelope.openLink = FuseOpenLink.with { $0.url = url.absoluteString }
        transport.broadcast(envelope)
        return true
    }

    public static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// The first http(s) link in some text, for "open what I copied".
    public static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url).first(where: isWebLink)
    }

    private func send(_ action: FusePhoneCommand.Action) {
        var envelope = transport.newEnvelope()
        envelope.phoneCommand = FusePhoneCommand.with { $0.action = action }
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case .openLink(let link):
            guard let url = URL(string: link.url), Self.isWebLink(url) else {
                return sendOutcome(.openLink, ok: false, detail: "Only web links open on the Mac.")
            }
            onOpenLink?(url)
        case .outcome(let outcome):
            onOutcome?(Outcome(kind: Outcome.Kind(outcome.kind), ok: outcome.ok, detail: outcome.detail))
        default:
            break
        }
    }
}

/// What became of something one device asked of the other (`Outcome` on the wire).
public struct Outcome: Equatable {
    public enum Kind: Equatable {
        case reply, openNotification, unlock, openLink, other

        init(_ wire: FuseOutcome.Kind) {
            switch wire {
            case .reply: self = .reply
            case .openNotification: self = .openNotification
            case .unlock: self = .unlock
            case .openLink: self = .openLink
            default: self = .other
            }
        }

        var wire: FuseOutcome.Kind {
            switch self {
            case .reply: return .reply
            case .openNotification: return .openNotification
            case .unlock: return .unlock
            case .openLink: return .openLink
            case .other: return .unspecified
            }
        }
    }

    public let kind: Kind
    public let ok: Bool
    /// A sentence for a person: why it failed and what to do. May be empty.
    public let detail: String
}
