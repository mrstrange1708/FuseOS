import AppKit
import FuseOSCore
import SwiftUI

/// Design review without a phone, a server, or a screen-recording permission.
///
/// Launch a debug build with `FUSE_DEMO=<dir>` and the app skips sign-in and networking,
/// fills itself with sample devices, clips and transfers, renders every tab in dark and
/// light to `<dir>/<appearance>-<tab>.png`, and quits. Debug builds only: release has no
/// way in.
enum DemoMode {
    #if DEBUG
    static let directory: URL? = ProcessInfo.processInfo.environment["FUSE_DEMO"].map { URL(fileURLWithPath: $0) }
    #else
    static let directory: URL? = nil
    #endif

    static var isOn: Bool { directory != nil }

    /// Posted with the tab's raw value; ShellView switches to it.
    static let showSection = Notification.Name("fuse.demo.showSection")

    /// The view model the demo filled, for rendering the popover outside the window.
    @MainActor private static var viewModel: DashboardViewModel?

    @MainActor
    static func fill(_ vm: DashboardViewModel) {
        viewModel = vm
        let mac = DeviceItem(id: "mac", name: "Junaid's MacBook Pro", platform: "macos", online: true, battery: nil, trusted: true, isSelf: true)
        let phone = DeviceItem(id: "phone", name: "Realme 12 Pro", platform: "android", online: true, battery: 76, trusted: true, isSelf: false)
        vm.selfDevice = mac
        vm.allPeers = [phone]
        vm.presence = [phone.id: PeerPresence(online: true, battery: 76, publicKey: nil, lanAddress: nil)]
        vm.connected = [phone.id]
        let now = Date()
        vm.syncLatency = SyncLatency(lastMs: 38, p95Ms: 64, samples: 50)
        vm.recentNotifications = [
            PhoneNotification(id: "wa", appName: "WhatsApp", title: "Ananya", text: "Are we still on for 7?",
                              iconPNG: nil, postedAt: now.addingTimeInterval(-120), canReply: true),
            PhoneNotification(id: "bank", appName: "HDFC Bank", title: "Payment received", text: "₹2,400 credited to your account",
                              iconPNG: nil, postedAt: now.addingTimeInterval(-900)),
        ]
        vm.liveActivities = [
            "uber": PhoneNotification(
                id: "uber", appName: "Uber", title: "Driver arriving in 4 min", text: "White Swift · KA 01 AB 1234",
                iconPNG: nil, postedAt: now, canReply: false, ongoing: true, progress: 0.7, indeterminate: false,
            ),
        ]
        vm.nowPlaying = NowPlaying(
            appName: "Spotify", title: "Midnight City", artist: "M83", playing: true,
            positionMs: 95_000, positionAt: now, durationMs: 243_000, artwork: sampleImage(),
        )
        vm.history = [
            ClipEntry(id: 6, text: "https://github.com/mrstrange1708/FuseOS/pull/3", imageData: nil, mime: nil, fromSelf: true, at: now.addingTimeInterval(-40)),
            ClipEntry(id: 5, text: "Meet at the café on 5th at 7 — I'll grab a table by the window.", imageData: nil, mime: nil, fromSelf: false, at: now.addingTimeInterval(-600)),
            ClipEntry(id: 4, text: nil, imageData: sampleImage(), mime: "image/png", fromSelf: false, at: now.addingTimeInterval(-1800)),
            ClipEntry(id: 3, text: "import numpy as np\nfrom sklearn.preprocessing import StandardScaler", imageData: nil, mime: nil, fromSelf: true, at: now.addingTimeInterval(-3600)),
            ClipEntry(id: 2, text: "OTP 482913", imageData: nil, mime: nil, fromSelf: false, at: now.addingTimeInterval(-7200)),
        ]
        vm.transfers = [
            TransferProgress(transferId: "t1", name: "Quarterly report.pdf", outgoing: true, bytes: 6_400_000, total: 10_000_000, state: .active),
            TransferProgress(transferId: "t2", name: "IMG_2041.HEIC", outgoing: false, bytes: 3_100_000, total: 3_100_000, state: .done),
        ]
    }

    /// Renders each tab of the main window to PNG, in dark then light, then quits.
    @MainActor
    static func snapshot(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        // A window closed in the last session is not restored at launch; open it.
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return NSApp.terminate(nil) }
        window.setContentSize(NSSize(width: 1080, height: 760))
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            for section in FuseSection.allCases {
                NotificationCenter.default.post(name: showSection, object: section.rawValue)
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "\(appearance == .darkAqua ? "dark" : "light")-\(section.rawValue.lowercased()).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
            }
        }
        // A wide window, where Home spreads to three columns.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 1680, height: 980))
        NotificationCenter.default.post(name: showSection, object: FuseSection.home.rawValue)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let view = window.contentView?.superview ?? window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("dark-home-wide.png"))
        }
        await snapshotPopover(to: directory)
        NSApp.terminate(nil)
    }

    /// The menu bar popover, in both appearances, caught mid-pulse so the spark shows.
    @MainActor
    private static func snapshotPopover(to directory: URL) async {
        guard let vm = viewModel else { return }
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let host = NSHostingView(rootView: MenuBarContent(viewModel: vm).environmentObject(SessionStore.shared))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(nanoseconds: 400_000_000)
            vm.pulse(toPhone: false)
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let name = "\(appearance == .darkAqua ? "dark" : "light")-popover.png"
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
            window.orderOut(nil)
        }
    }

    private static func sampleImage() -> Data? {
        let size = NSSize(width: 480, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.3, alpha: 1), NSColor(red: 0.35, green: 0.2, blue: 0.55, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 35)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
