import SwiftUI
import FuseOSCore

/// One device, with presence and battery. Shared by every pane and the connect space.
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
