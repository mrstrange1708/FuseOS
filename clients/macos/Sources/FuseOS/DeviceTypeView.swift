import SwiftUI
import FuseOSCore

/// The device kinds a user can pick after signing in. Only Android and macOS are
/// supported in v1; iOS and Windows are shown but not yet available.
struct DeviceType: Identifiable {
    let id: String
    let label: String
    let available: Bool

    static let all: [DeviceType] = [
        DeviceType(id: "android", label: "Android", available: true),
        DeviceType(id: "macos", label: "macOS", available: true),
        DeviceType(id: "ios", label: "Apple iOS phone", available: false),
        DeviceType(id: "windows", label: "Windows", available: false),
    ]

    static func label(for id: String) -> String {
        all.first { $0.id == id }?.label ?? id
    }
}

/// Post-login step: "What device is this?" Picking an available type advances to
/// Home; the unsupported ones just say "Coming soon".
struct DeviceTypeView: View {
    @EnvironmentObject var session: SessionStore
    @State private var comingSoon: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark()
                Spacer().frame(height: 30)

                Text("What device is this?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(FuseColor.ink)
                Text("Choose the platform you're setting up.")
                    .font(.system(size: 14))
                    .foregroundStyle(FuseColor.muted)
                    .padding(.top, 6)

                Spacer().frame(height: 26)

                VStack(spacing: 12) {
                    ForEach(DeviceType.all) { device in
                        DeviceTypeButton(device: device) { select(device) }
                    }
                }

                if let comingSoon {
                    Text("\(comingSoon) — Coming soon")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                        .padding(.top, 16)
                }

                Spacer().frame(height: 24)
                SwitchRow(prompt: "Not you?", action: "Sign out") { session.clear() }
            }
            .padding(32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FuseColor.bg)
    }

    private func select(_ device: DeviceType) {
        if device.available {
            session.setDeviceType(device.id)
        } else {
            comingSoon = device.label
        }
    }
}

/// A device row styled like the app: available ones read as primary choices,
/// unavailable ones are dimmed.
private struct DeviceTypeButton: View {
    let device: DeviceType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(device.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(device.available ? FuseColor.ink : FuseColor.muted)
                Spacer(minLength: 0)
                if !device.available {
                    Text("Coming soon")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(FuseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(device.available ? FuseColor.accent.opacity(0.6) : FuseColor.outline, lineWidth: 1),
            )
        }
        .buttonStyle(.plain)
    }
}
