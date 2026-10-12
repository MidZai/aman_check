import Foundation
import os.log

/// History of readings, one file per drive.
///
/// Format: JSON Lines (`<key>.jsonl`), one reading per line, append-only. A reading every
/// 30 s therefore adds ~170 bytes to the file, instead of rewriting the whole history (up to ~2 MB
/// after 30 days, i.e. several GB written per day to the SSD being monitored).
/// The file is only rewritten during compaction, once an hour.
///
/// Old `<key>.json` files (JSON array, v0.2 to v0.9) are converted on first read.
public final class HistoryStore: @unchecked Sendable {
    /// Can be replaced before first use (demo mode: temporary folder).
    public static var shared = HistoryStore()

    /// The app's Application Support folder (same as the bundle identifier).
    public static let defaultFolderName = "io.github.aman-disk.AmanDisk"
    /// Full resolution is kept for this long.
    public static let fullResolutionWindow: TimeInterval = 24 * 3600
    /// Size of the compaction buckets beyond 24 h.
    public static let compactionBucket: TimeInterval = 5 * 60
    /// Beyond this, readings are deleted.
    public static let retention: TimeInterval = 30 * 24 * 3600
    /// Two readings closer than this are considered duplicates.
    public static let minimumSpacing: TimeInterval = 15

    // `.utility` rather than `.background`: I/O at “background” QoS is heavily throttled
    // by macOS, and the interface sometimes waits for these reads.
    private let queue = DispatchQueue(label: "io.github.aman-disk.history", qos: .utility)
    private let historyFolderURL: URL
    /// In-memory cache, sorted by date: the file is read only once per drive.
    private var cache: [String: [HistorySample]] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL? = nil) {
        if let base = baseURL {
            historyFolderURL = base.appendingPathComponent("History")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            historyFolderURL = appSupport.appendingPathComponent(Self.defaultFolderName).appendingPathComponent("History")
        }
        try? FileManager.default.createDirectory(at: historyFolderURL, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - Files

    private func fileURL(for key: String) -> URL {
        historyFolderURL.appendingPathComponent("\(key).jsonl")
    }

    private func legacyFileURL(for key: String) -> URL {
        historyFolderURL.appendingPathComponent("\(key).json")
    }

    /// Call on `queue`.
    private func loadRaw(key: String) -> [HistorySample] {
        if let cached = cache[key] { return cached }
        var samples: [HistorySample] = []
        let url = fileURL(for: key)
        if let data = try? Data(contentsOf: url) {
            samples = decodeLines(data)
        }
        // Old format: JSON array. Converted once, then deleted.
        let legacyURL = legacyFileURL(for: key)
        if let data = try? Data(contentsOf: legacyURL) {
            let legacy = (try? decoder.decode([HistorySample].self, from: data)) ?? []
            samples = Self.merge(legacy, samples)
            writeAll(key: key, samples: samples)
            try? FileManager.default.removeItem(at: legacyURL)
        }
        samples.sort { $0.date < $1.date }
        cache[key] = samples
        return samples
    }

    private func decodeLines(_ data: Data) -> [HistorySample] {
        var samples: [HistorySample] = []
        samples.reserveCapacity(data.count / 160)
        // A truncated line (power loss during a write) is simply ignored.
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            if let s = try? decoder.decode(HistorySample.self, from: Data(line)) {
                samples.append(s)
            }
        }
        return samples
    }

    /// Rewrites the whole file (compaction, merge, conversion). Call on `queue`.
    private func writeAll(key: String, samples: [HistorySample]) {
        cache[key] = samples
        var data = Data()
        data.reserveCapacity(samples.count * 170)
        for s in samples {
            guard let line = try? encoder.encode(s) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        do {
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            os_log("Failed to write history: %{public}@", type: .error, error.localizedDescription)
        }
    }

    /// Appends a line at the end of the file. Call on `queue`.
    private func appendLine(key: String, sample: HistorySample) {
        guard var line = try? encoder.encode(sample) else { return }
        line.append(UInt8(ascii: "\n"))
        let url = fileURL(for: key)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                return
            } catch {
                // Fallback below: full rewrite.
            }
        }
        writeAll(key: key, samples: cache[key] ?? [sample])
    }

    private static func merge(_ a: [HistorySample], _ b: [HistorySample]) -> [HistorySample] {
        var byDate: [Date: HistorySample] = [:]
        for s in a { byDate[s.date] = s }
        for s in b { byDate[s.date] = s }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Adds a reading (already filtered). Call on `queue`.
    /// Retention is applied by the hourly compaction, not on every reading.
    private func add(_ sample: HistorySample, key: String) {
        var samples = loadRaw(key: key)
        if let last = samples.last, sample.date < last.date {
            // Reading older than the last one (clock changed): inserted in its place.
            samples.append(sample)
            samples.sort { $0.date < $1.date }
            writeAll(key: key, samples: samples)
            return
        }
        samples.append(sample)
        cache[key] = samples
        appendLine(key: key, sample: sample)
    }

    // MARK: - Writing

    /// Legacy append (v0.2): rejects readings within 4 min and 3 °C of the previous one.
    public func append(_ sample: HistorySample, for key: String) {
        queue.async {
            if let last = self.loadRaw(key: key).last {
                let timeDiff = sample.date.timeIntervalSince(last.date)
                if timeDiff > 0 && timeDiff < (4 * 60) {
                    let tempDiff = abs((sample.temperatureC ?? 0) - (last.temperatureC ?? 0))
                    if tempDiff < 3 { return }
                }
            }
            self.add(sample, key: key)
            // v0.2 behavior: readings that are too old are purged immediately.
            let cutoff = Date().addingTimeInterval(-Self.retention)
            if let first = self.cache[key]?.first, first.date < cutoff {
                self.writeAll(key: key, samples: (self.cache[key] ?? []).filter { $0.date >= cutoff })
            }
        }
    }

    /// Full-resolution append, used by continuous monitoring (one reading every 30 s).
    /// Only duplicates (less than 15 s apart) are ignored.
    public func record(_ sample: HistorySample, for key: String) {
        queue.async {
            if let last = self.loadRaw(key: key).last, abs(sample.date.timeIntervalSince(last.date)) < Self.minimumSpacing {
                return
            }
            self.add(sample, key: key)
        }
    }

    /// Compacts all histories: full resolution for 24 h, 5-minute buckets up to 30 days.
    public func compactAll(now: Date = Date()) {
        queue.sync {
            for key in self.allKeys() {
                let samples = loadRaw(key: key)
                let compacted = Self.compact(samples, now: now)
                if compacted != samples {
                    writeAll(key: key, samples: compacted)
                }
            }
        }
    }

    /// Keys present on disk (new and old format) or in memory. Call on `queue`.
    private func allKeys() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil)) ?? []
        let onDisk = files
            .filter { $0.pathExtension == "jsonl" || $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Set(onDisk).union(cache.keys)
    }

    /// Retention rule, without side effects (testable).
    public static func compact(_ samples: [HistorySample], now: Date) -> [HistorySample] {
        let retentionCutoff = now.addingTimeInterval(-retention)
        let fullResCutoff = now.addingTimeInterval(-fullResolutionWindow)

        let sorted = samples.filter { $0.date >= retentionCutoff }.sorted { $0.date < $1.date }
        let old = sorted.filter { $0.date < fullResCutoff }
        let recent = sorted.filter { $0.date >= fullResCutoff }

        var buckets: [TimeInterval: [HistorySample]] = [:]
        for sample in old {
            let start = floor(sample.date.timeIntervalSince1970 / compactionBucket) * compactionBucket
            buckets[start, default: []].append(sample)
        }

        let compacted: [HistorySample] = buckets.keys.sorted().compactMap { start in
            guard let group = buckets[start], let last = group.last else { return nil }
            // Bucket already compacted and on its own: kept as is.
            if group.count == 1, group[0].isCompacted { return group[0] }

            var weightedSum = 0.0
            var weight = 0
            var minT: Int? = nil
            var maxT: Int? = nil
            for s in group {
                guard let t = s.temperatureC else { continue }
                let n = s.measurementCount
                weightedSum += Double(t) * Double(n)
                weight += n
                let lo = s.temperatureMinC ?? t
                let hi = s.temperatureMaxC ?? t
                minT = min(minT ?? lo, lo)
                maxT = max(maxT ?? hi, hi)
            }
            return HistorySample(
                date: Date(timeIntervalSince1970: start),
                temperatureC: weight > 0 ? Int((weightedSum / Double(weight)).rounded()) : nil,
                percentageUsed: last.percentageUsed,
                dataUnitsWritten: last.dataUnitsWritten,
                dataUnitsRead: last.dataUnitsRead,
                powerOnHours: last.powerOnHours,
                mediaErrors: last.mediaErrors,
                availableSpare: last.availableSpare,
                temperatureMinC: minT,
                temperatureMaxC: maxT,
                sampleCount: group.reduce(0) { $0 + $1.measurementCount }
            )
        }

        return compacted + recent
    }

    // MARK: - Reading

    /// Synchronous read (command-line tool, tests). From the interface, prefer the `async` version.
    public func samples(for key: String, since: Date) -> [HistorySample] {
        queue.sync { Self.suffix(of: loadRaw(key: key), since: since) }
    }

    /// Read without blocking the main thread.
    public func loadSamples(for key: String, since: Date) async -> [HistorySample] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.suffix(of: self.loadRaw(key: key), since: since))
            }
        }
    }

    /// Readings after `since` in a sorted array (binary search).
    private static func suffix(of sorted: [HistorySample], since: Date) -> [HistorySample] {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].date < since { lo = mid + 1 } else { hi = mid }
        }
        return Array(sorted[lo...])
    }

    /// Merges an old history file (JSON array) into the history of `key`.
    public func importSamples(from url: URL, for key: String) {
        guard let data = try? Data(contentsOf: url),
              let imported = try? decoder.decode([HistorySample].self, from: data),
              !imported.isEmpty else { return }
        queue.sync {
            let existing = loadRaw(key: key)
            writeAll(key: key, samples: Self.merge(imported, existing))
        }
    }

    /// Clears the whole temperature history.
    public func removeAll() {
        queue.sync {
            cache.removeAll()
            let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" || file.pathExtension == "json" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Space used on disk by the history, in bytes.
    public func diskUsageBytes() -> UInt64 {
        queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + UInt64(size)
            }
        }
    }

    public func folderPath() -> String {
        historyFolderURL.path
    }
}
