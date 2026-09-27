import Foundation

/// The other device's battery and charging, live over the LAN (`DeviceStatus`).
public struct PeerStatus: Equatable {
    public let battery: Int?
    public let charging: Bool
}

/// Sends this Mac's battery and charging when a channel comes up and when they change, and
/// reports the phone's.
@MainActor
public final class DeviceStatusLink {
    public var onPeerStatus: ((PeerStatus) -> Void)?
    private let transport: LanTransport
    private var observer: AnyObject?
    private var lastSent: (Int, Bool)?

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onStatusEnvelope = { [weak self] envelope in self?.receive(envelope) }
        observer = Battery.observe { [weak self] in
            Task { @MainActor in self?.send(force: false) }
        }
    }

    /// `force` for a new channel, which has heard nothing yet.
    public func send(force: Bool) {
        let battery = Battery.currentPercent() ?? -1
        let charging = Battery.isCharging()
        if !force, let lastSent, lastSent == (battery, charging) { return }
        lastSent = (battery, charging)
        var envelope = transport.newEnvelope()
        envelope.deviceStatus = FuseDeviceStatus.with {
            $0.battery = Int32(battery)
            $0.charging = charging
        }
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        guard case .deviceStatus(let s) = envelope.body else { return }
        onPeerStatus?(PeerStatus(battery: s.battery >= 0 ? Int(s.battery) : nil, charging: s.charging))
    }
}
