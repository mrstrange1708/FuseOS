import SwiftUI
import FuseOSCore

/// The connect space: this device, the device it's linking to, and the one thing to do next.
///
/// It advances on its own as presence and the LAN channel change — there is nothing to
/// refresh, nothing to poll, and nothing to press. Signing in on the phone is the entire
/// link step; the rest happens while the user watches. Only the last stage offers
/// Continue, so reaching the rest of the app means a real encrypted channel exists, not
/// merely that both devices are online.
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

            LinkDiagram(
                stage: state.stage,
                selfName: viewModel.selfDevice?.name ?? session.deviceName ?? "This Mac",
                peerName: peer?.name ?? "Your phone",
                peerCaption: peerCaption,
            )
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
        case .alone: return "Sign in on your phone"
        case .peerOffline: return "Open FuseOS on your phone"
        case .differentNetwork: return "Same WiFi, please"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }

    private var detail: String {
        switch state.stage {
        case .alone:
            return "Install FuseOS on your phone and sign in with this same account. There is no code to scan — the two link themselves. Nothing you copy ever leaves your network."
        case .peerOffline:
            return "\(peer?.name ?? "Your phone") is on this account but isn't running FuseOS right now."
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
        case .alone: return "not signed in yet"
        case .peerOffline: return "offline"
        case .differentNetwork: return "different network"
        case .connecting: return "connecting…"
        case .connected: return "connected · direct"
        }
    }

    @ViewBuilder private var action: some View {
        switch state.stage {
        case .connected:
            PrimaryButton(title: "Continue", action: onContinue)
        case .alone, .peerOffline, .differentNetwork, .connecting:
            // Deliberately no Continue here: past this screen the app assumes a live
            // channel, so letting someone through early only moves the confusion later.
            // Every stage clears itself, so the only offer is the manual fallback —
            // understated, because reaching for it usually means waiting would have worked.
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
                Spacer()
                Button("Link manually") { showPairing = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.accent)
            }
        }
    }
}

/// The two devices, the link between them, and the mark that lights when it is live.
///
/// This is the whole status in one picture, so it is drawn rather than described: a phone
/// and a laptop as recognisable silhouettes, a channel between them that carries a pulse
/// while dialling and goes solid on connect, and the FuseOS mark riding the middle of it.
private struct LinkDiagram: View {
    let stage: ConnectStage
    let selfName: String
    let peerName: String
    let peerCaption: String

    private var isLive: Bool { stage == .connected }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                DeviceFigure(kind: .phone, lit: isLive)
                    .frame(width: 52, height: 78)
                LinkChannel(stage: stage)
                    .frame(height: 78)
                DeviceFigure(kind: .laptop, lit: true)
                    .frame(width: 104, height: 78)
            }

            HStack(spacing: 0) {
                Caption(title: peerName, detail: peerCaption, lit: isLive)
                    .frame(maxWidth: .infinity)
                Caption(title: selfName, detail: "this device", lit: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private struct Caption: View {
        let title: String
        let detail: String
        let lit: Bool

        var body: some View {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// A phone or a laptop, drawn rather than borrowed from SF Symbols so the two read as the
/// same family and the screen can light up independently of the body.
private struct DeviceFigure: View {
    enum Kind { case phone, laptop }

    let kind: Kind
    let lit: Bool

    private var bodyStroke: Color { lit ? FuseColor.ink.opacity(0.75) : FuseColor.outline }
    private var screenFill: Color { lit ? FuseColor.accent.opacity(0.16) : FuseColor.surfaceAlt }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            switch kind {
            case .phone:
                let bodyRect = CGRect(x: w * 0.12, y: h * 0.06, width: w * 0.76, height: h * 0.88)
                ZStack {
                    RoundedRectangle(cornerRadius: w * 0.16)
                        .fill(screenFill)
                        .frame(width: bodyRect.width, height: bodyRect.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: w * 0.16)
                                .stroke(bodyStroke, lineWidth: 1.6),
                        )
                    // The speaker slot: the one detail that stops a rounded rectangle
                    // from reading as a generic tile.
                    Capsule()
                        .fill(bodyStroke.opacity(0.7))
                        .frame(width: bodyRect.width * 0.28, height: 2)
                        .offset(y: -bodyRect.height * 0.38)
                }
                .frame(width: w, height: h)

            case .laptop:
                let lidW = w * 0.74
                let lidH = h * 0.68
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(screenFill)
                        .frame(width: lidW, height: lidH)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(bodyStroke, lineWidth: 1.6))
                    // The base is wider than the lid and barely tall — that proportion is
                    // the entire reason this reads as a laptop and not as a monitor.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bodyStroke.opacity(0.85))
                        .frame(width: w, height: 4)
                }
                .frame(width: w, height: h, alignment: .center)
            }
        }
    }
}

/// The channel between the devices: a rail, a pulse that runs it while dialling, and the
/// FuseOS mark sitting on top of it.
private struct LinkChannel: View {
    let stage: ConnectStage

    @State private var pulseAt: CGFloat = 0
    @State private var shine = false

    private var isLive: Bool { stage == .connected }
    private var isDialling: Bool { stage == .connecting }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let midY = geometry.size.height / 2

            ZStack {
                // The rail. Dashed until a channel exists, solid once one does — a broken
                // line for a broken link is the one piece of this that needs no caption.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: w, y: midY))
                }
                .stroke(
                    isLive ? FuseColor.accent : FuseColor.outline,
                    style: StrokeStyle(
                        lineWidth: isLive ? 2 : 1.5,
                        dash: isLive ? [] : [4, 5],
                    ),
                )

                // The pulse: a comet that runs device-to-device while we dial. This is the
                // preloader — it says "something is happening" without a spinner, and it
                // travels in the direction the connection is being made.
                if isDialling {
                    LinearGradient(
                        colors: [FuseColor.accent.opacity(0), FuseColor.accent, FuseColor.accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing,
                    )
                    .frame(width: w * 0.4, height: 2)
                    .position(x: pulseAt * w, y: midY)
                }

                // The mark rides the middle of the rail, and lights only when the channel
                // is real — so the logo itself is the status.
                ZStack {
                    Circle()
                        .fill(FuseColor.bg)
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(isLive ? FuseColor.accent : FuseColor.outline, lineWidth: isLive ? 1.5 : 1)
                        .frame(width: 34, height: 34)
                    FuseMark(height: 12)
                        .opacity(isLive ? 1 : 0.45)
                }
                .shadow(color: FuseColor.accent.opacity(isLive && shine ? 0.55 : 0), radius: 14)
                .scaleEffect(isLive && shine ? 1.06 : 1)
                .position(x: w / 2, y: midY)
            }
            .onAppear { restart() }
            .onChange(of: stage) { _ in restart() }
        }
    }

    /// Animations are driven from the stage rather than left running, so a screen sitting
    /// at `peerOffline` for an hour is not repainting a comet nobody is watching.
    private func restart() {
        pulseAt = 0
        shine = false
        if isDialling {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulseAt = 1
            }
        }
        if isLive {
            // One breath on arrival, then settle. A logo that pulses forever stops meaning
            // "it just connected" and starts meaning nothing.
            withAnimation(.easeOut(duration: 0.45)) { shine = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.45)) { shine = false }
        }
    }
}
