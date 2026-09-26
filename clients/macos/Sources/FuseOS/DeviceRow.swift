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
        DeviceCard(
            platform: device.platform,
            name: device.name,
            status: isConnected ? "Linked · direct" : (presence.online ? "Online" : "Offline"),
            lit: isConnected || presence.online,
            battery: presence.battery,
        )
    }
}

/// One device as a card: glyph, name, where it stands, battery.
struct DeviceCard: View {
    let platform: String
    let name: String
    let status: String
    let lit: Bool
    let battery: Int?

    var body: some View {
        HStack(spacing: 14) {
            deviceGlyph(platform: platform, online: lit)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(lit ? FuseColor.accent : FuseColor.muted).frame(width: 6, height: 6)
                    Text(status)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
                }
            }
            Spacer(minLength: 0)
            BatteryBadge(percent: battery)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .panelSurface(radius: 16)
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
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
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


/// This Mac, in the same shape as a peer row.
///
/// Home used to list only peers, which left the machine you are standing at missing from
/// its own dashboard — the one device whose name you need to recognise when the phone
/// shows it back to you.
struct SelfDeviceRow: View {
    let name: String?

    var body: some View {
        DeviceCard(
            platform: "macos",
            name: name ?? SessionStore.detectedDeviceName(),
            status: "This Mac",
            lit: true,
            battery: nil,
        )
    }
}
