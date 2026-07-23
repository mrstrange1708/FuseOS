import Foundation
import IOKit.ps

/// Reads this Mac's battery percentage (nil on desktops with no battery).
/// Battery is operational presence metadata — never a user payload.
enum Battery {
    static func currentPercent() -> Int? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let capacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                maximum > 0
            else { continue }
            return Int((Double(capacity) / Double(maximum) * 100).rounded())
        }
        return nil
    }
}
