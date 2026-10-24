import SwiftUI
import AppKit

/// FuseOS palette — "Filament": cool slate devices, one warm ember accent (the link).
/// Colors resolve to light or dark automatically via the system appearance.
enum FuseColor {
    static let accent = dynamic(0xE85D2A, 0xFF7A45)
    /// The website's second warm note: tails, beads and the far end of every gradient.
    static let amber = dynamic(0xD9831F, 0xFFB347)
    /// Ember to amber — the headline gradient the website uses; for the one word per screen that earns it.
    static let glow = LinearGradient(colors: [accent, amber], startPoint: .leading, endPoint: .trailing)
    static let bg = dynamic(0xF1F3F7, 0x0C0E14)
    static let surface = dynamic(0xFFFFFF, 0x161922)
    static let surfaceAlt = dynamic(0xF2F4F8, 0x1C202A)
    static let ink = dynamic(0x14171F, 0xECEFF4)
    static let muted = dynamic(0x59616F, 0x98A0AD)
    static let outline = dynamic(0xCDD3DD, 0x343B47)
    static let error = dynamic(0xC0341B, 0xFF8A75)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? nsColor(dark) : nsColor(light)
        })
    }

    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            alpha: 1.0,
        )
    }
}

/// One motion vocabulary, in Apple's terms (response, damping) rather than durations.
/// Critically damped by default — no overshoot on a pane or a menu that simply appears;
/// a little bounce only where something arrives with momentum. Springs start from wherever
/// the view is now, so every one of these can be interrupted mid-flight.
enum FuseMotion {
    /// Moves and state changes.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Press and hover: quick enough to read as contact.
    static let quick = Animation.spring(response: 0.2, dampingFraction: 1)
    /// Something landed — a clip crossed, the island opened, the phone appeared.
    static let arrive = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// The user asked macOS for less motion: cross-fades instead of slides and bounces.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Feedback on the press itself, not the release: the control dips the moment it is
/// touched and springs back when let go. Wide rows pass a gentler scale — 3% of a full-width
/// row is a lurch, not a dip.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .animation(FuseMotion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

/// Account → Appearance. System follows macOS, and is the default.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    static let key = "appearance"
    static var saved: AppearanceMode {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    /// Set on the app rather than a window, so the window, the menu bar popover and the
    /// island all change together; FuseColor resolves against whatever this picks.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
