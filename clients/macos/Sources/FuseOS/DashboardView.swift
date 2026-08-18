import SwiftUI
import FuseOSCore

/// The main screen after login + device-type selection: this device and the
/// devices it's connected to, with live presence and battery.
struct DashboardView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showPairing = false

    var body: some View {
        ScrollView {
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
                Spacer().frame(height: 28)

                Text("THIS DEVICE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FuseColor.accent)
                Spacer().frame(height: 8)
                thisDeviceCard

                Spacer().frame(height: 26)
                HStack {
                    Text("Connected devices")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                    Spacer()
                    Text("\(viewModel.peers.count)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
                Spacer().frame(height: 12)

                if viewModel.peers.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(viewModel.peers) { peer in
                            DeviceRow(
                                device: peer,
                                presence: viewModel.onlineState(for: peer),
                                isConnected: viewModel.isConnected(peer),
                            )
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error).padding(.top, 16)
                }

                Spacer().frame(height: 22)
                PrimaryButton(title: "Connect a device") { showPairing = true }

                Spacer().frame(height: 30)
                clipboardHistory
            }
            .padding(32)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FuseColor.bg)
        .onAppear { viewModel.start() }
        .sheet(isPresented: $showPairing) {
            PairingView(viewModel: viewModel).environmentObject(session)
        }
    }

    private var thisDeviceCard: some View {
        HStack(spacing: 14) {
            deviceGlyph(platform: session.deviceType ?? "macos", online: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.selfDevice?.name ?? (session.email ?? "This Mac"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                Text("This device · online")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
            }
            Spacer(minLength: 0)
            BatteryBadge(percent: viewModel.selfDevice?.battery ?? Battery.currentPercent())
        }
        .padding(16)
        .background(FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuseColor.outline.opacity(0.6), lineWidth: 1))
    }

    private var emptyState: some View {
        Text("No devices yet. Tap “Connect a device” to pair your phone or Mac.")
            .font(.system(size: 14))
            .foregroundStyle(FuseColor.muted)
            .padding(.vertical, 8)
    }

    /// Everything copied on this Mac or received from a peer, newest first.
    ///
    /// This is also the diagnostic for "sync isn't working": an item that appears here
    /// marked "Copied here" but never reaches the phone places the failure on the LAN
    /// channel, not on the clipboard capture.
    private var clipboardHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                Spacer()
                Text(viewModel.connected.isEmpty ? "not connected" : "syncing")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(viewModel.connected.isEmpty ? FuseColor.muted : FuseColor.accent)
            }
            Spacer().frame(height: 12)

            if viewModel.history.isEmpty {
                Text("Nothing yet. Copy something here, or copy on your phone with FuseOS "
                     + "on screen, and it lands here.")
                    .font(.system(size: 14))
                    .foregroundStyle(FuseColor.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.history) { entry in
                        ClipRow(entry: entry) { viewModel.copyToClipboard(entry) }
                    }
                }
            }
        }
    }
}

/// One clipboard item. Clicking it copies it back to this Mac's clipboard.
struct ClipRow: View {
    let entry: ClipEntry
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.fromSelf ? "Copied here" : "From your phone")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FuseColor.accent)
                Spacer()
                Text(entry.at, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FuseColor.muted)
            }

            if let data = entry.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(entry.text ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FuseColor.outline.opacity(0.6), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
    }
}

/// One connected device with presence + battery.
struct DeviceRow: View {
    let device: DeviceItem
    let presence: PeerPresence
    /// A direct encrypted LAN channel, which is stronger than merely being online:
    /// online means the server can see it, connected means we can talk to it.
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 14) {
            deviceGlyph(platform: device.platform, online: presence.online)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                Text(statusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(presence.online ? FuseColor.accent : FuseColor.muted)
            }
            Spacer(minLength: 0)
            BatteryBadge(percent: presence.battery)
        }
        .padding(16)
        .background(FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuseColor.outline.opacity(0.6), lineWidth: 1))
    }

    private var statusText: String {
        if isConnected { return "\(device.platform) · connected · direct" }
        return "\(device.platform) · \(presence.online ? "online" : "offline")"
    }
}

struct BatteryBadge: View {
    let percent: Int?

    var body: some View {
        if let percent {
            HStack(spacing: 5) {
                Image(systemName: symbol(for: percent))
                    .font(.system(size: 13))
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(percent <= 20 ? FuseColor.error : FuseColor.muted)
        } else {
            EmptyView()
        }
    }

    private func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

@ViewBuilder
func deviceGlyph(platform: String, online: Bool) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 12)
            .fill(FuseColor.accent.opacity(online ? 0.14 : 0.08))
            .frame(width: 44, height: 44)
        Image(systemName: platform == "android" ? "iphone" : "laptopcomputer")
            .font(.system(size: 20))
            .foregroundStyle(online ? FuseColor.accent : FuseColor.muted)
    }
}
