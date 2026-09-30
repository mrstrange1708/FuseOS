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
    /// The eye: a password you can check before you send it is one you get right first time.
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isSecure && !revealed {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
                if isSecure {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(FuseColor.muted)
                    }
                    .buttonStyle(.plain)
                    .help(revealed ? "Hide password" : "Show password")
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

/// The link between the two devices, drawn as a live wave. At rest it drifts gently — the
/// link is alive, not just drawn. Each crossing sends a wave packet from the sender to the
/// receiver, which lands as an opening ring; a file in flight keeps packets flowing.
struct LiveFilament: View {
    let linked: Bool
    let pulse: LinkPulse?
    var stream: Bool? = nil
    @State private var sparkStart: Date?
    @State private var toPhone = true

    private static let travel = 0.7
    private static let landing = 0.5

    var body: some View {
        // 30 fps is plenty for a slow wave, and it idles only while linked and on screen.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !linked)) { timeline in
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
        let w = size.width, mid = size.height / 2
        let t = now.timeIntervalSinceReferenceDate
        guard linked else {
            var rail = Path()
            rail.move(to: CGPoint(x: 0, y: mid))
            rail.addLine(to: CGPoint(x: w, y: mid))
            g.stroke(rail, with: .color(FuseColor.muted.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            return
        }
        // Packets on the wire right now: (centre 0…1 along the link, strength).
        var packets: [(Double, Double)] = []
        if let stream {
            for i in 0..<3 {
                let p = (t / 1.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                packets.append((stream ? p : 1 - p, sin(p * .pi)))
            }
        }
        var landed: Double?
        if let sparkStart {
            let elapsed = now.timeIntervalSince(sparkStart)
            if elapsed < Self.travel {
                let p = elapsed / Self.travel
                let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                packets.append((toPhone ? e : 1 - e, 1))
            } else {
                landed = min(1, (elapsed - Self.travel) / Self.landing)
            }
        }
        func y(_ x: CGFloat) -> CGFloat {
            let u = Double(x / max(w, 1))
            // Pinned at both ends: the wave leaves one device and enters the other.
            let ends = sin(u * .pi)
            var dy = sin(u * 4 * .pi - t * 1.8) * 2.2 * ends
            for (c, strength) in packets {
                let d = (u - c) * Double(w) / 26
                dy += sin(Double(x) / 5 - t * 18) * 10 * strength * exp(-d * d) * ends
            }
            return mid + CGFloat(dy)
        }
        var wave = Path()
        wave.move(to: CGPoint(x: 0, y: y(0)))
        for x in stride(from: CGFloat(2), through: w, by: 2) { wave.addLine(to: CGPoint(x: x, y: y(x))) }
        let busy = !packets.isEmpty
        // A soft glow under the line while something is crossing.
        if busy {
            g.stroke(wave, with: .color(FuseColor.amber.opacity(0.18)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        g.stroke(wave, with: .linearGradient(
            Gradient(colors: [FuseColor.accent.opacity(0.35), busy ? FuseColor.amber : FuseColor.accent.opacity(0.8), FuseColor.accent.opacity(0.35)]),
            startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: w, y: mid),
        ), style: StrokeStyle(lineWidth: busy ? 2.2 : 1.6, lineCap: .round))
        if let landed {
            let x = toPhone ? w : 0
            let r = 5 + 20 * landed
            g.stroke(Path(ellipseIn: CGRect(x: x - r, y: mid - r, width: r * 2, height: r * 2)),
                     with: .color(FuseColor.amber.opacity(1 - landed)), lineWidth: 1.8)
        }
    }
}

/// Rings rippling out from the centre: a search in progress.
struct Ripples: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0 ..< 3, id: \.self) { i in
                    let phase = (t / 2.1 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(FuseColor.accent.opacity(0.7 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(0.25 + phase * 0.95)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A battery as a ring, the way the menu bar's own widgets show it; a bolt while charging.
struct BatteryRing: View {
    let percent: Int
    var charging = false
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().stroke(FuseColor.outline.opacity(0.6), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, percent))) / 100)
                .stroke(percent <= 20 && !charging ? FuseColor.error : FuseColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(FuseColor.accent)
            } else {
                Text("\(percent)")
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(FuseColor.ink)
            }
        }
        .frame(width: size, height: size)
        .help(charging ? "Charging, \(percent)%" : "Battery \(percent)%")
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
