import Foundation
import Security

/// The wire side of nearby lock and unlock: a fresh beacon key for the phone on every
/// channel, "I was just unlocked" both ways, and the check before an away-lock
/// (`BeaconKey`, `Unlocked`, `BeaconCheck`).
@MainActor
public final class ProximityLink {
    /// The key the phone's beacon is being derived from right now. Kept on disk, like the
    /// phone keeps it: after either side restarts, the beacon must still be recognised
    /// before the next channel comes up — or nearby lock and unlock go blind.
    public private(set) var beaconKey: Data? = UserDefaults.standard.data(forKey: ProximityLink.keyDefault)
    static let keyDefault = "beaconKey"
    public var onBeaconKeyChanged: ((Data) -> Void)?
    public var onPeerUnlocked: (() -> Void)?
    /// The phone's answer to `checkBeacon()`: whether its beacon is on.
    public var onBeaconChecked: ((Bool) -> Void)?

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
        UserDefaults.standard.set(key, forKey: Self.keyDefault)
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

    /// Bluetooth says the phone is far: ask it, over the LAN, to beacon at full power.
    public func checkBeacon() {
        var envelope = transport.newEnvelope()
        envelope.beaconCheck = FuseBeaconCheck()
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case .unlocked: onPeerUnlocked?()
        case .beaconCheck(let check): onBeaconChecked?(check.broadcasting)
        default: break
        }
    }
}
