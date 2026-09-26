import Foundation

/// What the phone is playing (`MediaState`), as plain values for the app target.
public struct NowPlaying: Equatable {
    public let appName: String
    public let title: String
    public let artist: String
    public let playing: Bool
    /// The position at `positionAt`; while playing, the current position is later.
    public let positionMs: Int64
    public let positionAt: Date
    public let durationMs: Int64
    public let artwork: Data?

    public init(
        appName: String, title: String, artist: String, playing: Bool,
        positionMs: Int64, positionAt: Date, durationMs: Int64, artwork: Data?,
    ) {
        self.appName = appName
        self.title = title
        self.artist = artist
        self.playing = playing
        self.positionMs = positionMs
        self.positionAt = positionAt
        self.durationMs = durationMs
        self.artwork = artwork
    }

    /// Where the track is at `now`, advanced by the wall clock while playing.
    public func position(at now: Date) -> Int64 {
        guard playing else { return positionMs }
        let advanced = positionMs + Int64(now.timeIntervalSince(positionAt) * 1000)
        return durationMs > 0 ? min(advanced, durationMs) : advanced
    }
}

/// The Mac's side of Now Playing: follows `MediaState`, sends `MediaCommand`.
@MainActor
public final class MediaRemote {
    public var onChange: ((NowPlaying?) -> Void)?
    public private(set) var current: NowPlaying?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onMediaEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    public func playPause() { send(.playPause) }
    public func next() { send(.next) }
    public func previous() { send(.previous) }
    public func seek(toMs position: Int64) { send(.seek, position: position) }

    private func send(_ action: FuseMediaCommand.Action, position: Int64 = 0) {
        var envelope = transport.newEnvelope()
        envelope.mediaCommand = FuseMediaCommand.with {
            $0.action = action
            $0.positionMs = position
        }
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        guard case .mediaState(let state) = envelope.body else { return }
        guard state.active else {
            current = nil
            onChange?(nil)
            return
        }
        // Artwork travels once per track; a later state for the same track keeps it.
        let sameTrack = current?.title == state.title && current?.artist == state.artist
        let artwork = state.artworkJpeg.isEmpty ? (sameTrack ? current?.artwork : nil) : state.artworkJpeg
        current = NowPlaying(
            appName: state.appName, title: state.title, artist: state.artist, playing: state.playing,
            positionMs: state.positionMs,
            positionAt: Date(timeIntervalSince1970: Double(state.positionAtUnixMs) / 1000),
            durationMs: state.durationMs, artwork: artwork,
        )
        onChange?(current)
    }

    /// Nothing is playing once the phone is gone.
    public func peerGone() {
        current = nil
        onChange?(nil)
    }
}
