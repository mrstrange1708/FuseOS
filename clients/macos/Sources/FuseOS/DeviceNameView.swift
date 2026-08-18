import SwiftUI
import FuseOSCore

/// Post-login step: name this Mac.
///
/// This replaces a "What device is this?" platform picker. The app is a Mac; asking the
/// user to tell it so was a question it already knew the answer to, the answer was ignored
/// by registration (which hardcodes the platform), and picking wrong only ever produced a
/// Mac that drew itself as a phone.
///
/// The name is the thing that actually needs a human: the other device shows it in every
/// list, and "Junaid's MacBook" is worth more there than the hostname.
struct DeviceNameView: View {
    @EnvironmentObject var session: SessionStore
    @State private var name: String = SessionStore.detectedDeviceName()

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark()
                Spacer().frame(height: 30)

                Text("Name this Mac")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(FuseColor.ink)
                Text("This is how it appears on your other devices. You can change it later.")
                    .font(.system(size: 14))
                    .foregroundStyle(FuseColor.muted)
                    .padding(.top, 6)

                Spacer().frame(height: 26)

                FuseTextField(title: "Device name", text: $name)
                    .onSubmit(save)

                Spacer().frame(height: 20)
                PrimaryButton(title: "Continue", action: save)
                    // An empty name would show as a blank row on the phone, so the only
                    // way past this screen is with something to display.
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                    .disabled(trimmed.isEmpty)

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

    private func save() {
        guard !trimmed.isEmpty else { return }
        session.setDeviceName(trimmed)
    }
}
