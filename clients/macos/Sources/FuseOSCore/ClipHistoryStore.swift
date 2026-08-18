import Foundation

/// Keeps clipboard history across app launches.
///
/// On disk, not in the control plane: clipboard content never reaches the server or its
/// database (see CLAUDE.md). This is local storage on the machine that already has the
/// content on its pasteboard, which is a different thing from shipping it anywhere.
///
/// Text lives in one JSON index; image bytes go to files beside it, referenced by name.
/// Base64-ing a 2 MB screenshot into JSON would triple it and force the whole history to
/// be parsed to read one entry.
public struct ClipHistoryStore {
    private let directory: URL
    private var index: URL { directory.appendingPathComponent("history.json") }
    private var blobs: URL { directory.appendingPathComponent("blobs", isDirectory: true) }

    /// Defaults to Application Support, which is where user data that is not a document
    /// belongs and what Time Machine backs up.
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuseOS/clip-history", isDirectory: true)
    }

    private struct Record: Codable {
        var id: Int
        var text: String?
        var mime: String?
        var blob: String?
        var fromSelf: Bool
        var atUnixMs: Int64
    }

    public func load() -> [ClipEntry] {
        guard let data = try? Data(contentsOf: index),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }

        return records.compactMap { record in
            var imageData: Data?
            if let blob = record.blob {
                // An entry whose blob went missing is dropped rather than shown as an
                // empty card the user cannot do anything with.
                guard let bytes = try? Data(contentsOf: blobs.appendingPathComponent(blob)) else {
                    return nil
                }
                imageData = bytes
            }
            return ClipEntry(
                id: record.id,
                text: record.text,
                imageData: imageData,
                mime: record.mime,
                fromSelf: record.fromSelf,
                at: Date(timeIntervalSince1970: Double(record.atUnixMs) / 1000),
            )
        }
    }

    /// Writes the whole list. Small and bounded, so a full rewrite beats incremental edits.
    public func save(_ entries: [ClipEntry]) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: blobs, withIntermediateDirectories: true)

        var keep = Set<String>()
        let records: [Record] = entries.map { entry in
            var blob: String?
            if let data = entry.imageData {
                let name = "\(entry.id).bin"
                try? data.write(to: blobs.appendingPathComponent(name))
                keep.insert(name)
                blob = name
            }
            return Record(
                id: entry.id,
                text: entry.text,
                mime: entry.mime,
                blob: blob,
                fromSelf: entry.fromSelf,
                atUnixMs: Int64(entry.at.timeIntervalSince1970 * 1000),
            )
        }

        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: index)
        }
        // Evicted entries leave their blobs behind otherwise, and images are the only
        // thing here big enough to matter.
        let existing = (try? fileManager.contentsOfDirectory(atPath: blobs.path)) ?? []
        for name in existing where !keep.contains(name) {
            try? fileManager.removeItem(at: blobs.appendingPathComponent(name))
        }
    }

    /// Sign-out must not leave the last user's copied content on disk.
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// How far back the history list shows. Mirrors `HistoryWindow` on Android.
public enum HistoryWindow: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: return "24 hours"
        case .week: return "7 days"
        case .month: return "30 days"
        case .all: return "All"
        }
    }

    /// Nil means everything still held — the caps in `ClipboardSync` bound that, not time.
    var seconds: TimeInterval? {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        case .all: return nil
        }
    }

    public func filter(_ entries: [ClipEntry], now: Date = Date()) -> [ClipEntry] {
        guard let seconds else { return entries }
        let cutoff = now.addingTimeInterval(-seconds)
        return entries.filter { $0.at >= cutoff }
    }
}
