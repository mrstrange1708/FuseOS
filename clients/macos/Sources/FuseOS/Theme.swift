import SwiftUI
import AppKit

/// FuseOS palette — "Filament": cool slate devices, one warm ember accent (the link).
/// Colors resolve to light or dark automatically via the system appearance.
enum FuseColor {
    static let accent = dynamic(0xE85D2A, 0xFF7A45)
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
