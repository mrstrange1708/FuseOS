import Foundation
import IOKit.ps

/// Reads this Mac's battery percentage (nil on desktops with no battery).
/// Battery is operational presence metadata — never a user payload.
public enum Battery {
    public static func currentPercent() -> Int? {
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

    /// Whether this Mac is on its charger (plugged in and not full counts as charging).
    public static func isCharging() -> Bool {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSIsChargingKey as String] as? Bool == true { return true }
            if description[kIOPSPowerSourceStateKey as String] as? String == kIOPSACPowerValue { return true }
        }
        return false
    }

    /// Calls `onChange` whenever a power source changes (plugged, unplugged, a percent),
    /// driven by IOKit's notification rather than a timer. Keep the returned token alive.
    public static func observe(_ onChange: @escaping () -> Void) -> AnyObject? {
        let box = CallbackBox(onChange)
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().callback()
        }, context)?.takeRetainedValue() else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        box.source = source
        return box
    }

    private final class CallbackBox {
        let callback: () -> Void
        var source: CFRunLoopSource?
        init(_ callback: @escaping () -> Void) { self.callback = callback }
        deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) } }
    }
}
