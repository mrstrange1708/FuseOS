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
