import Foundation

/// Where the control plane lives. In core rather than the app target because
/// `SignalClient` needs it and the app's networking does too.
public enum Config {
    /// The FuseOS control-plane server. `pnpm --filter server dev` runs it on :3000.
    ///
    /// `localhost` assumes the server runs on this Mac — which is also why Android's
    /// `Config.BASE_URL` is built from this Mac's LAN IP rather than the same string
    /// (injected by the `android` pane in `mprocs.yaml`). The two clients only reach
    /// the same server under that assumption.
    public static let baseURL = URL(string: "http://localhost:3000")!
    /// The `/signal` presence WebSocket on the same server.
    public static let signalURL = URL(string: "ws://localhost:3000/signal")!
}
