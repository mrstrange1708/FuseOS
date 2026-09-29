import Foundation

/// How fast clips cross, measured as the round trip from sending a clip to the peer's
/// `Ack` that it applied it. A round trip, because two devices' clocks cannot be trusted
/// to agree to the millisecond; it bounds the one-way time from above, so a round trip
/// under the PRD's 300 ms p95 means the copy-to-available time is too.
public struct SyncLatency: Equatable {
    public let lastMs: Int
    public let p95Ms: Int
    public let samples: Int

    public init(lastMs: Int, p95Ms: Int, samples: Int) {
        self.lastMs = lastMs
        self.p95Ms = p95Ms
        self.samples = samples
    }
}

/// The most recent samples, bounded, and their summary.
struct LatencyWindow {
    private(set) var samples: [Int] = []
    let capacity: Int

    init(capacity: Int = 50) {
        self.capacity = capacity
    }

    mutating func record(_ ms: Int) -> SyncLatency {
        samples.append(ms)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        let sorted = samples.sorted()
        // Nearest-rank p95: the smallest sample at or above 95% of the rest.
        let rank = Int((Double(sorted.count) * 0.95).rounded(.up)) - 1
        return SyncLatency(lastMs: ms, p95Ms: sorted[max(0, rank)], samples: sorted.count)
    }
}

/// Which round trips measure the link. Two things make one measure something else, and
/// either one alone pinned the p95 at seconds, or minutes, while clips crossed in 30 ms:
///
/// - **A side asleep.** A dozing phone (or a sleeping Mac) leaves frames in the socket
///   buffer until it wakes. So a frame older than `staleMs` on arrival is neither answered
///   (an echo, a clip's Ack) nor timed (an echo, an Ack) — it waited on a sleeper.
/// - **A queue.** One connection carries images, history, file chunks and screen frames;
///   a heartbeat behind a 2 MB image times the image. A round trip counts only if no bulk
///   frame crossed while it was in flight. Mirrors `RoundTrip` on Android.
enum RoundTrip {
    /// ponytail: wall clocks of two NTP-synced devices; a skew past this stops heartbeat
    /// samples (none shown, never wrong ones) — send the peer's hold time if that bites.
    static let staleMs: Int64 = 2_000

    static func isFresh(sentAtUnixMs: Int64, nowUnixMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        nowUnixMs - sentAtUnixMs <= staleMs
    }

    /// The round trip in ms, or nil when a bulk frame crossed after `sentAt` (uptime ns).
    static func ms(sentAt: UInt64, now: UInt64, lastBulkAt: UInt64) -> Int? {
        guard lastBulkAt < sentAt, now >= sentAt else { return nil }
        return Int((now - sentAt) / 1_000_000)
    }

    /// Envelopes big enough to queue a heartbeat behind them.
    static func isBulk(_ envelope: FuseEnvelope) -> Bool {
        switch envelope.body {
        case .clipImage, .historySync, .fileChunk, .screenFrame, .sidecarFrame, .mediaState: true
        default: false
        }
    }
}
