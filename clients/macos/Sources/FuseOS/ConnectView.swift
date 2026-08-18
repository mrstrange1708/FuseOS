import SwiftUI
import FuseOSCore

/// The connect space: this device, the device it's linking to, and the one thing to do next.
///
/// It advances on its own as presence and the LAN channel change — there is nothing to
/// refresh and nothing to poll. Only the last stage offers Continue, so reaching the rest
/// of the app means a real encrypted channel exists, not merely that both devices are online.
struct ConnectView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    let onContinue: () -> Void

    @State private var showPairing = false

    private var state: ConnectState { viewModel.connectState }

    /// The peer being connected to, or the only paired peer while it is still offline.
    private var peer: DeviceItem? {
        state.peerId.flatMap { id in viewModel.peers.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                SecondaryButton(title: "Sign out") {
                    viewModel.stop()
                    session.clear()
                }
                .frame(width: 110)
            }

            Spacer(minLength: 24)

            VStack(spacing: 0) {
                DeviceChip(
                    name: viewModel.selfDevice?.name ?? session.deviceName ?? "This Mac",
                    platform: "macos",
                    caption: "This device",
                    lit: true,
                )
                LinkBeam(stage: state.stage)
                DeviceChip(
                    name: peer?.name ?? "Your other device",
                    platform: peer?.platform ?? "android",
                    caption: peerCaption,
                    lit: state.stage == .connected,
                )
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 24)

            Text(headline)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Spacer().frame(height: 6)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 20)
            action

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error).padding(.top, 16)
            }
        }
        .padding(32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FuseColor.bg)
        .onAppear { viewModel.start() }
        .sheet(isPresented: $showPairing) {
            PairingView(viewModel: viewModel).environmentObject(session)
        }
    }

    // MARK: - Per-stage copy

    private var headline: String {
        switch state.stage {
        case .notPaired: return "Connect your phone"
        case .peerOffline: return "Open FuseOS on your phone"
        case .differentNetwork: return "Same WiFi, please"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }

    private var detail: String {
        switch state.stage {
        case .notPaired:
            return "Scan a code once and these two devices stay linked. Nothing you copy ever leaves your network."
        case .peerOffline:
            return "\(peer?.name ?? "Your phone") is paired but isn't running FuseOS right now."
        case .differentNetwork:
            let mine = state.selfSubnet.map { "\($0).x" } ?? "another network"
            let theirs = state.peerSubnet.map { "\($0).x" } ?? "another network"
            return "This Mac is on \(mine) and \(peer?.name ?? "your phone") is on \(theirs). They have to share a network to talk directly."
        case .connecting:
            return "Both devices are on the same network. Opening a direct encrypted channel."
        case .connected:
            return "Your clipboard and files now move straight between these devices over your network."
        }
    }

    private var peerCaption: String {
        switch state.stage {
        case .notPaired: return "Not paired yet"
        case .peerOffline: return "offline"
        case .differentNetwork: return "different network"
        case .connecting: return "connecting…"
        case .connected: return "connected · direct"
        }
    }

    @ViewBuilder private var action: some View {
        switch state.stage {
        case .notPaired:
            PrimaryButton(title: "Scan a code") { showPairing = true }
        case .connected:
            PrimaryButton(title: "Continue", action: onContinue)
        case .peerOffline, .differentNetwork, .connecting:
            // Deliberately no Continue here: past this screen the app assumes a live
            // channel, so letting someone through early only moves the confusion later.
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
                Spacer()
                Button("Pair another device") { showPairing = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.accent)
            }
        }
    }
}

/// One device in the connect diagram.
private struct DeviceChip: View {
    let name: String
    let platform: String
    let caption: String
    let lit: Bool

    var body: some View {
        HStack(spacing: 14) {
            deviceGlyph(platform: platform, online: lit)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                Text(caption)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuseColor.outline.opacity(0.6), lineWidth: 1))
    }
}

/// The line between the two devices — the whole status in one glance.
private struct LinkBeam: View {
    let stage: ConnectStage
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(stage == .connected ? FuseColor.accent : FuseColor.outline)
                .frame(width: 2, height: 34)
                .opacity(stage == .connecting && pulse ? 0.25 : 1)
                .animation(
                    stage == .connecting
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse,
                )
        }
        .onAppear { pulse = true }
    }
}
