import Foundation

/// The Mac's side of `PhoneCommand` and `OpenLink`: ring the phone, ask it for a photo,
/// hand a link over — and open the links the phone hands back.
@MainActor
public final class PhoneCommands {
    /// A link the phone sent to open here (http/https only; anything else never arrives).
    public var onOpenLink: ((URL) -> Void)?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onActionEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    public func ring() { send(.ring) }
    public func stopRinging() { send(.stopRing) }
    /// The photo comes back as a clip, so it lands on this Mac's clipboard.
    public func takePhoto() { send(.takePhoto) }

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
        guard case .openLink(let link) = envelope.body,
              let url = URL(string: link.url), Self.isWebLink(url) else { return }
        onOpenLink?(url)
    }
}
