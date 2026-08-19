import SwiftUI
import CoreImage.CIFilterBuiltins
import FuseOSCore

/// Link two of your devices by hand — the safety net behind automatic linking.
///
/// Devices on one account link themselves, so this is not how linking normally happens and
/// nothing here grants trust. It forces the introduction that `/signal` usually delivers on
/// its own: the code (or the QR carrying it) hands the other device this one's public key
/// and LAN address, for when presence has gone stale or a socket never came back.
struct PairingView: View {
    @ObservedObject var viewModel: DashboardViewModel
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
        .frame(width: 400, height: 560)
        .background(FuseColor.bg)
        // The point of the sheet is a live channel, so it closes the moment there is one
        // — whichever side of the code this device was on.
        .onChange(of: viewModel.connectState.stage) { stage in
            if stage == .connected { dismiss() }
        }
    }

    private var showCode: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(code == nil
                 ? "Only needed if the two didn't find each other on their own."
                 : "Scan this with your phone — or type the code into it.")
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
            Spacer().frame(height: 20)

            if let code {
                // The QR keeps its own light background in dark mode: a scanner needs the
                // dark-on-light contrast it was encoded with.
                QRCode(text: PairingCode.uri(code), size: 180)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: 20)
                CodeCells(code: PairingCode.normalize(code), activeIndex: nil)
                Spacer().frame(height: 12)
                Text("Expires in 5 minutes · waiting for the other device…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
                    .frame(maxWidth: .infinity)
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
            Spacer().frame(height: 20)
            CodeField(code: $enteredCode, onComplete: claim)
            Spacer().frame(height: 20)
            PrimaryButton(title: "Pair", loading: busy) { claim() }
        }
    }

    private func generate() {
        busy = true
        error = nil
        Task {
            do {
                code = try await viewModel.initiatePairing()
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func claim() {
        let normalized = PairingCode.normalize(enteredCode)
        guard normalized.count == PairingCode.length else {
            error = "Enter all \(PairingCode.length) characters of the code."
            return
        }
        guard !busy else { return }  // the field auto-submits on the 8th character
        busy = true
        error = nil
        Task {
            do {
                try await viewModel.claimPairing(code: normalized)
                dismiss()
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Code cells

/// The code as `XXXX-XXXX` in one box per character. `activeIndex` lights the cell the
/// next keystroke will fill; nil for a read-only display.
private struct CodeCells: View {
    let code: String
    let activeIndex: Int?

    var body: some View {
        HStack(spacing: 7) {
            cells(0..<4)
            Text("-")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(FuseColor.muted)
                .padding(.horizontal, 1)
            cells(4..<8)
        }
        .frame(maxWidth: .infinity)
    }

    private func cells(_ range: Range<Int>) -> some View {
        let chars = Array(code)
        return ForEach(range, id: \.self) { index in
            let character = index < chars.count ? String(chars[index]) : ""
            let active = index == activeIndex
            Text(character)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(FuseColor.ink)
                .frame(width: 34, height: 46)
                .background(FuseColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? FuseColor.accent : FuseColor.outline,
                                lineWidth: active ? 2 : 1),
                )
        }
    }
}

/// Eight boxes that behave like one text field: a real (invisible) `TextField` takes the
/// keystrokes — so paste, delete and the caret all work — while the cells draw the state.
/// Anything typed is normalized, so lowercase becomes uppercase as you go.
private struct CodeField: View {
    @Binding var code: String
    let onComplete: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .focused($focused)
                .onChange(of: code) { new in
                    let normalized = PairingCode.normalize(new)
                    if normalized != code { code = normalized }
                    if normalized.count == PairingCode.length { onComplete() }
                }
                .onSubmit(onComplete)
                // Invisible but still focusable and hit-testable — fully transparent
                // views stop taking key input on some macOS versions.
                .opacity(0.01)

            CodeCells(code: code, activeIndex: focused ? min(code.count, PairingCode.length - 1) : nil)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }
}

// MARK: - QR

/// QR for the pairing URI. CoreImage generates it — no dependency, and the payload is
/// small enough that the default correction level scans instantly.
private struct QRCode: View {
    let text: String
    let size: CGFloat

    var body: some View {
        if let image = Self.render(text, size: size) {
            Image(nsImage: image)
                .interpolation(.none)  // keep the module edges crisp when scaled
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(FuseColor.surfaceAlt)
                .frame(width: size, height: size)
                .overlay(Text("QR unavailable").font(.system(size: 11)).foregroundStyle(FuseColor.muted))
        }
    }

    private static func render(_ text: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
