import Foundation
import Security

/// The wire side of nearby lock and unlock: a fresh beacon key for the phone on every
/// channel, and "I was just unlocked" both ways (`BeaconKey`, `Unlocked`).
@MainActor
public final class ProximityLink {
    /// The key the phone's beacon is being derived from right now (nil before a channel).
    public private(set) var beaconKey: Data?
    public var onBeaconKeyChanged: ((Data) -> Void)?
    public var onPeerUnlocked: (() -> Void)?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onProximityEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    /// A new channel: hand the phone a new random key.
    public func sendBeaconKey() {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return }
        let key = Data(bytes)
        beaconKey = key
        onBeaconKeyChanged?(key)
        var envelope = transport.newEnvelope()
        envelope.beaconKey = FuseBeaconKey.with { $0.key = key }
        transport.broadcast(envelope)
    }

    /// This Mac was just unlocked: wake the phone.
    public func sendUnlocked() {
        var envelope = transport.newEnvelope()
        envelope.unlocked = FuseUnlocked()
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        if case .unlocked = envelope.body { onPeerUnlocked?() }
    }
}
