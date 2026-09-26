import AppKit
import ApplicationServices
import FuseOSCore

/// Acts on the phone's trackpad and keyboard input by posting real mouse and key events.
///
/// Two gates, both required: the user's "Let your phone control this Mac" switch (off by
/// default), and macOS Accessibility access for FuseOS, without which posting events is
/// silently ignored by the system anyway.
@MainActor
final class MacPointer {
    static let enabledKey = "phoneControlsMac"

    private var dragging = false
    private let source = CGEventSource(stateID: .hidSystemState)

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Whether macOS lets FuseOS post input; with `prompt`, asks the user if not.
    @discardableResult
    static func accessibilityGranted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ event: PointerEvent) {
        guard isEnabled, AXIsProcessTrusted() else { return }
        switch event {
        case let .move(dx, dy): move(dx: dx, dy: dy)
        case .click: click(.left, count: 1)
        case .doubleClick: click(.left, count: 2)
        case .rightClick: click(.right, count: 1)
        case let .scroll(dx, dy):
            CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                    wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
                .post(tap: .cghidEventTap)
        case .dragStart:
            dragging = true
            post(.leftMouseDown, at: cursor, button: .left)
        case .dragEnd:
            dragging = false
            post(.leftMouseUp, at: cursor, button: .left)
        case let .text(text): type(text)
        case let .key(code, modifiers): key(code, modifiers: modifiers)
        }
    }

    // MARK: - Mouse

    /// Where the cursor is, in the top-left-origin coordinates CGEvent uses.
    private var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func move(dx: Double, dy: Double) {
        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union(Self.cgFrame(of: $1)) }
        let current = cursor
        let next = CGPoint(
            x: min(max(current.x + dx, bounds.minX), bounds.maxX - 1),
            y: min(max(current.y + dy, bounds.minY), bounds.maxY - 1),
        )
        post(dragging ? .leftMouseDragged : .mouseMoved, at: next, button: .left)
    }

    /// One press and release. A double-click is the phone's second tap, sent with a click
    /// count of 2 — the first tap already went as a single click, as on a real trackpad.
    private func click(_ button: CGMouseButton, count: Int) {
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for type in [down, up] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor, mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event?.post(tap: .cghidEventTap)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    /// An NSScreen frame (bottom-left origin) in CGEvent's top-left-origin space.
    private static func cgFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    // MARK: - Keyboard

    private func type(_ text: String) {
        let units = Array(text.utf16)
        for chunk in stride(from: 0, to: units.count, by: 20) {
            let slice = Array(units[chunk..<min(chunk + 20, units.count)])
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func key(_ code: UInt16, modifiers: UInt32) {
        var flags: CGEventFlags = []
        if modifiers & 1 != 0 { flags.insert(.maskCommand) }
        if modifiers & 2 != 0 { flags.insert(.maskShift) }
        if modifiers & 4 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 8 != 0 { flags.insert(.maskControl) }
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
