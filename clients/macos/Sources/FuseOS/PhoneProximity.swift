import CoreBluetooth
import FuseOSCore
import Foundation

/// How close the phone is, from its Bluetooth beacon's signal strength.
///
/// The phone advertises a rotating value only this Mac can recognise (`BeaconToken`); this
/// scans for it and keeps a smoothed RSSI. Near and far have a gap between them so a
/// reading on the edge does not flap, and "far" also covers not hearing the phone at all
/// for a while — out of range is as far as it gets.
final class PhoneProximity: NSObject, CBCentralManagerDelegate {
    enum Range: Equatable { case unknown, near, far }

    /// Stronger than this (dBm, smoothed) is near — the phone on the desk or in a pocket.
    static let nearRSSI = -72.0
    /// Weaker than this is far — across the flat, down the corridor.
    static let farRSSI = -88.0
    /// Not heard for this long counts as far.
    static let silence: TimeInterval = 25

    private(set) var range: Range = .unknown {
        didSet { if range != oldValue { onRangeChanged?(range); onChange?() } }
    }
    var onRangeChanged: ((Range) -> Void)?
    /// Range or Bluetooth itself changed — for the settings line that says what is wrong.
    var onChange: (() -> Void)?
    /// Bluetooth on this Mac, as CoreBluetooth last said; `.unknown` while not scanning.
    private(set) var bluetooth: CBManagerState = .unknown
    /// The key the beacon is derived from; nil until the phone has linked once.
    var key: Data?

    private var central: CBCentralManager?
    private var smoothed: Double?
    private var lastHeard: Date?
    private var silenceCheck: Timer?

    /// Starts scanning. macOS asks for Bluetooth the first time.
    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
        // A beacon going silent sends nothing; this is the only way to notice it.
        silenceCheck = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkSilence() }
    }

    func stop() {
        central?.stopScan()
        central = nil
        silenceCheck?.invalidate()
        silenceCheck = nil
        bluetooth = .unknown
        range = .unknown
        onChange?()
    }

    /// Why this Mac cannot tell the phone is close, in words for the user; nil when it can.
    var problem: String? {
        switch bluetooth {
        case .poweredOff: return "Bluetooth is off on this Mac."
        case .unauthorized: return "Allow FuseOS in System Settings → Privacy & Security → Bluetooth."
        case .unsupported: return "This Mac has no Bluetooth LE."
        default: break
        }
        switch range {
        case .near: return nil
        case .far: return "Your phone is too far away (or its Bluetooth is off)."
        case .unknown: return "Can't hear your phone yet. Open FuseOS on it and allow Nearby devices."
        }
    }

    /// Heard recently and close.
    var isNear: Bool { range == .near }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetooth = central.state
        onChange?()
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let key, let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 10, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xFF else { return }
        let token = data.subdata(in: data.startIndex + 2 ..< data.startIndex + 10)
        guard BeaconToken.current(key: key).contains(token) else { return }
        let rssi = RSSI.doubleValue
        guard rssi < 0 else { return } // 127 means "unavailable"
        smoothed = smoothed.map { $0 * 0.75 + rssi * 0.25 } ?? rssi
        lastHeard = Date()
        classify()
    }

    private func classify() {
        guard let smoothed else { return }
        if smoothed >= Self.nearRSSI {
            range = .near
        } else if smoothed <= Self.farRSSI {
            range = .far
        } else if range == .unknown {
            range = .near
        }
    }

    private func checkSilence() {
        guard let lastHeard, Date().timeIntervalSince(lastHeard) > Self.silence else { return }
        smoothed = nil
        range = .far
    }
}
