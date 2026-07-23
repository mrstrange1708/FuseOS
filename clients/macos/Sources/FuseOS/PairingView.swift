import SwiftUI
import FuseOSCore

/// Connect two of your devices: show a code on one and enter it on the other.
struct PairingView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case show = "Show a code"
        case enter = "Enter a code"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .show
    @State private var code: String?
    @State private var busy = false
    @State private var error: String?
    @State private var enteredCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connect a device")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FuseColor.ink)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.plain).foregroundStyle(FuseColor.muted)
            }
            Spacer().frame(height: 18)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer().frame(height: 22)

            switch mode {
            case .show: showCode
            case .enter: enterCode
            }

            if let error {
                ErrorBanner(message: error).padding(.top, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 380, height: 420)
        .background(FuseColor.bg)
        .onChange(of: viewModel.pairedCount) { _ in dismiss() }
    }

    private var showCode: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show this code on your other device and enter it there.")
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
            Spacer().frame(height: 20)

            if let code {
                Text(code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(FuseColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(FuseColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer().frame(height: 12)
                Text("Expires in 5 minutes · waiting for the other device…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
            } else {
                PrimaryButton(title: "Generate a code", loading: busy) { generate() }
            }
        }
    }

    private var enterCode: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter the code shown on your other device.")
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
            Spacer().frame(height: 18)
            FuseTextField(title: "Pairing code", text: $enteredCode)
            Spacer().frame(height: 18)
            PrimaryButton(title: "Pair", loading: busy) { claim() }
        }
    }

    private func generate() {
        guard let deviceId = session.deviceId else {
            error = "This device isn't registered yet. Try again in a moment."
            return
        }
        busy = true
        error = nil
        Task {
            do {
                code = try await ControlPlane.initiatePairing(deviceId: deviceId).code
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func claim() {
        guard let deviceId = session.deviceId else {
            error = "This device isn't registered yet. Try again in a moment."
            return
        }
        let trimmed = enteredCode.trimmed
        guard !trimmed.isEmpty else {
            error = "Enter the pairing code."
            return
        }
        busy = true
        error = nil
        Task {
            do {
                _ = try await ControlPlane.claimPairing(deviceId: deviceId, code: trimmed)
                await viewModel.refresh()
                dismiss()
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }
}
