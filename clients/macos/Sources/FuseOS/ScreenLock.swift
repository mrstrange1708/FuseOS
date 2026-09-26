import Foundation

/// Locks the screen the way ⌃⌘Q does. The call lives in the private login framework —
/// there is no public API for it — so it is looked up at run time and simply does nothing
/// if a future macOS removes it.
enum ScreenLock {
    static let enabledKey = "lockWhenPhoneLeaves"

    static func lockNow() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }
}
