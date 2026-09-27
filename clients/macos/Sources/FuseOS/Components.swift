import SwiftUI

/// The FuseOS mark: a wired-through node and a lit ember node joined by a filament.
struct FuseMark: View {
    var height: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let h = size.height
            let cy = h / 2
            let r = h * 0.22
            let stroke = h * 0.10
            let leftX = r + stroke
            let rightX = size.width - r - stroke

            var line = Path()
            line.move(to: CGPoint(x: leftX, y: cy))
            line.addLine(to: CGPoint(x: rightX, y: cy))
            context.stroke(line, with: .color(FuseColor.ink.opacity(0.4)), lineWidth: stroke)

            let spark = Path(ellipseIn: CGRect(x: size.width / 2 - r * 0.5, y: cy - r * 0.5, width: r, height: r))
            context.fill(spark, with: .color(FuseColor.accent))

            let leftRing = Path(ellipseIn: CGRect(x: leftX - r, y: cy - r, width: r * 2, height: r * 2))
            context.stroke(leftRing, with: .color(FuseColor.ink), lineWidth: stroke)

            let rightNode = Path(ellipseIn: CGRect(x: rightX - r, y: cy - r, width: r * 2, height: r * 2))
            context.fill(rightNode, with: .color(FuseColor.accent))
        }
        .frame(width: height * 1.8, height: height)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            FuseMark(height: 22)
            HStack(spacing: 0) {
                Text("Fuse").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(FuseColor.ink)
                Text("OS").font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(FuseColor.muted)
            }
        }
    }
}

struct FuseTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(FuseColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(FuseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(error == nil ? FuseColor.outline : FuseColor.error, lineWidth: 1),
            )

            if let error {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FuseColor.error)
            }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if loading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(FuseColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FuseColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(FuseColor.outline, lineWidth: 1),
                )
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Text(message).font(.system(size: 14)).foregroundStyle(FuseColor.error)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FuseColor.error.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SwitchRow: View {
    let prompt: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(prompt).font(.system(size: 14)).foregroundStyle(FuseColor.muted)
            Button(action: onTap) {
                Text(action).font(.system(size: 14, weight: .semibold)).foregroundStyle(FuseColor.accent)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }
}

/// The one card surface: solid, a hairline edge, continuous corners. Glass is reserved for
/// the floating bar — the one place with content underneath worth showing through.
extension View {
    func panelSurface(radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(FuseColor.surface))
            .overlay(shape.stroke(FuseColor.outline.opacity(0.55), lineWidth: 1))
    }
}

/// A small rounded tile holding a symbol — the leading mark of every list row.
struct IconTile: View {
    let symbol: String
    var tint: Color = FuseColor.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
    }
}

/// The app's button: a capsule, ember-filled when it is the thing to press.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? FuseColor.error : FuseColor.accent
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : (destructive ? FuseColor.error : FuseColor.ink))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule().fill(prominent ? tint : FuseColor.surfaceAlt),
            )
            .overlay(Capsule().stroke(prominent ? Color.clear : FuseColor.outline.opacity(0.7), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Something just crossed the link, and which way. The filament animates one spark per
/// pulse, so the link visibly "does something" exactly when data moves.
struct LinkPulse: Equatable {
    let id = UUID()
    /// Mac → phone when true; phone → Mac when false.
    let toPhone: Bool
}

/// The line between this Mac (left) and the phone (right), driven by what actually moves:
/// a comet with an amber tail for each `LinkPulse`, in the direction the data went, and a
/// ring where it lands; beads streaming the whole time a file is in flight (`stream`, true
/// toward the phone). Idle, it rests with a dot in the middle and draws nothing per frame.
/// Not linked, a dim dashed gap.
struct LiveFilament: View {
    let linked: Bool
    let pulse: LinkPulse?
    var stream: Bool? = nil
    @State private var sparkStart: Date?
    @State private var toPhone = true

    private static let travel = 0.6
    private static let landing = 0.45

    var body: some View {
        TimelineView(.animation(paused: stream == nil && sparkStart == nil)) { timeline in
            Canvas { g, size in draw(&g, size: size, now: timeline.date) }
        }
        .onChange(of: pulse) { pulse in
            guard linked, let pulse else { return }
            let start = Date()
            toPhone = pulse.toPhone
            sparkStart = start
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.travel + Self.landing) {
                if sparkStart == start { sparkStart = nil }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, now: Date) {
        let w = size.width, y = size.height / 2
        var rail = Path()
        rail.move(to: CGPoint(x: 0, y: y))
        rail.addLine(to: CGPoint(x: w, y: y))
        guard linked else {
            g.stroke(rail, with: .color(FuseColor.muted.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            return
        }
        g.stroke(rail, with: .linearGradient(
            Gradient(colors: [FuseColor.accent.opacity(0.15), FuseColor.accent.opacity(0.5), FuseColor.accent.opacity(0.15)]),
            startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: w, y: y),
        ), lineWidth: 1.5)
        func dot(_ x: CGFloat, _ r: CGFloat, _ color: Color) {
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        if let stream {
            let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            for i in 0..<3 {
                let t = (phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                // Fading at both ends reads as leaving one device and entering the other.
                dot(stream ? t * w : (1 - t) * w, 2.5, FuseColor.amber.opacity(sin(t * .pi)))
            }
        } else if sparkStart == nil {
            dot(w / 2, 3, FuseColor.accent.opacity(0.85))
        }
        guard let sparkStart else { return }
        let elapsed = now.timeIntervalSince(sparkStart)
        if elapsed < Self.travel {
            let p = elapsed / Self.travel
            let t = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 // ease in-out
            let x = toPhone ? t * w : (1 - t) * w
            let tail = 60 * (1 - abs(0.5 - t))
            let from = CGPoint(x: toPhone ? max(0, x - tail) : min(w, x + tail), y: y)
            var streak = Path()
            streak.move(to: from)
            streak.addLine(to: CGPoint(x: x, y: y))
            g.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, FuseColor.amber]), startPoint: from, endPoint: CGPoint(x: x, y: y)),
                     style: StrokeStyle(lineWidth: 3, lineCap: .round))
            dot(x, 9, FuseColor.accent.opacity(0.25))
            dot(x, 4, FuseColor.amber)
        } else {
            // Landed: a ring opens at the receiving end and fades.
            let c = min(1, (elapsed - Self.travel) / Self.landing)
            let x = toPhone ? w : 0
            let r = 4 + 14 * c
            g.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(FuseColor.amber.opacity(1 - c)), lineWidth: 1.5)
        }
    }
}

/// A thin ember progress bar — the one used everywhere a thing is moving.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FuseColor.outline.opacity(0.6))
                Capsule()
                    .fill(FuseColor.accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: 4)
    }
}
