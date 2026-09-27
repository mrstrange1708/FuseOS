import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import OpenDirectory
import Security

/// Unlocks this Mac when the phone is unlocked next to it — experimental.
///
/// macOS has no API for a third party to unlock the screen (Apple Watch uses a private
/// one). What is possible is what a person does: wake the display and type the login
/// password. So, with the user's explicit opt-in, the password is checked against macOS
/// (Open Directory) and kept in the login Keychain, and typed at the lock screen when the
/// phone says it was unlocked *and* it is close by Bluetooth. Needs Accessibility (to type)
/// and may be refused by a macOS that blocks synthetic input at the lock screen.
enum MacUnlock {
    static let enabledKey = "unlockWithPhone"
    private static let keychainService = "com.fuseos.mac-unlock"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) && storedPassword() != nil }

    /// Whether the screen is locked right now.
    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Checks the password against this Mac's account before anything is stored.
    static func verify(_ password: String) -> Bool {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    static func store(_ password: String) {
        forget()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: Data(password.utf8),
            // Must be readable while the screen is locked — that is when it is needed.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func forget() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService] as CFDictionary)
    }

    private static func storedPassword() -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Wakes the display and types the password at the lock screen.
    static func unlock() {
        guard isEnabled, isScreenLocked, AXIsProcessTrusted(), let password = storedPassword() else { return }
        var assertion: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("FuseOS: phone unlocked nearby" as CFString, kIOPMUserActiveLocal, &assertion)
        // Give the lock screen a moment to come up and focus its password field.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let source = CGEventSource(stateID: .hidSystemState)
            let units = Array(password.utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.post(tap: .cghidEventTap)
            }
            for keyDown in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: keyDown)?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Asks for the password (once, when the user turns the feature on). False if refused.
    @MainActor
    static func setUp() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Unlock this Mac with your phone"
        alert.informativeText = "Enter this Mac's login password. FuseOS checks it with macOS, keeps it in your Keychain, and types it at the lock screen only when your phone is unlocked right next to this Mac. Experimental: a macOS update may stop it working."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Turn on")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard verify(field.stringValue) else {
            let wrong = NSAlert()
            wrong.messageText = "That's not this Mac's password"
            wrong.runModal()
            return false
        }
        store(field.stringValue)
        return true
    }
}
