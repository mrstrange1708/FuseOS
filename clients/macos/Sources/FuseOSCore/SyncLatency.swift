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
