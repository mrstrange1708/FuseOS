import Foundation
import FuseOSCore
import PostHog

/// PostHog for the app: "Application Opened" gives daily actives, and `Usage` in FuseOSCore
/// names each feature as it crosses the LAN channel — counts, never content (CLAUDE.md
/// principle 6). People are named by account id, as the server names them, so one person
/// counts once across phone, Mac and web. The project key only sends events, so it ships in
/// the app; `FusePostHogKey` in Info.plist overrides it, and an empty value turns it off.
enum Analytics {
    private static var started = false

    static func start() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "FusePostHogKey") as? String)
            ?? "phc_y8RWGPAEQYEDoMox8WcZk4gKuccTVDo9RWKadU6u62nw"
        guard !key.isEmpty else { return }
        let config = PostHogConfig(apiKey: key, host: "https://us.i.posthog.com")
        config.captureApplicationLifecycleEvents = true
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)
        #if DEBUG
        PostHogSDK.shared.register(["environment": "debug"])
        #else
        PostHogSDK.shared.register(["environment": "production"])
        #endif
        Usage.record = { feature in
            var properties: [String: Any] = ["feature": feature.name]
            properties.merge(feature.properties) { current, _ in current }
            PostHogSDK.shared.capture("feature_used", properties: properties)
        }
        started = true
    }

    static func identify(_ userId: String) {
        if started { PostHogSDK.shared.identify(userId) }
    }

    /// Signed out: the next person on this Mac is someone else.
    static func reset() {
        if started { PostHogSDK.shared.reset() }
    }

    /// The "Usage statistics" switch. PostHog keeps the choice across launches.
    static var enabled: Bool {
        get { started && !PostHogSDK.shared.isOptOut() }
        set {
            guard started else { return }
            if newValue { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
        }
    }
}
