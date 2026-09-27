import Foundation

/// Where the control plane lives. In core rather than the app target because
/// `SignalClient` needs it and the app's networking does too.
public enum Config {
    /// The FuseOS control-plane server: `FuseServerURL` in Info.plist, which
    /// `build-app.sh` writes from `FUSE_SERVER_URL` (the release workflow passes the
    /// hosted https URL). Unset — a dev build, or the tests — it is this Mac, where
    /// `pnpm --filter server dev` runs it on :3000; Android's dev URL is this Mac's LAN IP
    /// for the same reason (`mprocs.yaml`).
    public static let baseURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "FuseServerURL") as? String,
           let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }()

    /// The `/signal` presence WebSocket on the same server: ws for http, wss for https.
    public static let signalURL: URL = {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/signal"
        return components.url!
    }()
}


import os

/// Diagnostics for the data plane, readable with:
/// `log stream --predicate 'subsystem == "com.fuseos.app"' --level info`
///
/// Deliberately narrow: whether a channel exists, and why an inbound clip was refused.
/// Those two questions account for every "it says connected but nothing syncs" report,
/// and neither is answerable from outside the process without this. Never logs clipboard
/// content — payloads stay off every diagnostic surface (see docs/observability.md).
public enum FuseLog {
    public static let lan = Logger(subsystem: "com.fuseos.app", category: "lan")
    public static let clipboard = Logger(subsystem: "com.fuseos.app", category: "clipboard")
    /// Why nearby unlock did or did not act — every refusal used to be silent.
    public static let unlock = Logger(subsystem: "com.fuseos.app", category: "unlock")
}
