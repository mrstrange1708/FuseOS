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
