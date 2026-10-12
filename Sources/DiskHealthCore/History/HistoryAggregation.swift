import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7j"
    case thirtyDays = "30j"

    public var id: String { rawValue }

    public var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        }
    }

    /// Beyond 24 h, the chart shows the average and the min–max range.
    public var showsMinMaxBand: Bool {
        self == .sevenDays || self == .thirtyDays
    }

    /// Size of the buckets; nil = raw readings.
    var chunkSize: TimeInterval? {
        switch self {
        case .oneHour: return nil
        case .twentyFourHours: return 5 * 60
        case .sevenDays: return 60 * 60
        case .thirtyDays: return 4 * 60 * 60
        }
    }
}

public struct AggregatedPoint: Identifiable, Equatable {
    /// Stable identifier (the date): Swift Charts can diff two renders instead of redrawing everything.
    public var id: Date { date }
    public let date: Date
    public let temperature: Double
    public let segment: Int
    public let minTemperature: Double?
    public let maxTemperature: Double?

    public init(date: Date, temperature: Double, segment: Int, minTemperature: Double? = nil, maxTemperature: Double? = nil) {
        self.date = date
        self.temperature = temperature
        self.segment = segment
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
    }
}

public struct AggregationResult: Equatable {
    public static let empty = AggregationResult(points: [], min: nil, max: nil, average: nil, measurementCount: 0, gaps: [])

    public let points: [AggregatedPoint]
    public let min: Int?
    public let max: Int?
    public let average: Int?
    /// Number of real readings covered (compacted buckets count for their readings).
    public let measurementCount: Int
    /// Periods without readings (gaps) between two segments.
    public let gaps: [DateInterval]
}

public enum HistoryAggregation {
    /// Nominal interval of continuous monitoring.
    public static let nominalInterval: TimeInterval = 30

    public static func aggregate(samples: [HistorySample], range: HistoryRange) -> AggregationResult {
        let withTemp = samples.filter { $0.temperatureC != nil }
        if withTemp.isEmpty {
            return .empty
        }

        var minTemp: Int? = nil
        var maxTemp: Int? = nil
        var weightedSum = 0.0
        var count = 0
        for s in withTemp {
            guard let t = s.temperatureC else { continue }
            let lo = s.temperatureMinC ?? t
            let hi = s.temperatureMaxC ?? t
            minTemp = Swift.min(minTemp ?? lo, lo)
            maxTemp = Swift.max(maxTemp ?? hi, hi)
            weightedSum += Double(t) * Double(s.measurementCount)
            count += s.measurementCount
        }
        let avgTemp = count > 0 ? Int(round(weightedSum / Double(count))) : nil

        let points: [AggregatedPoint]
        if let chunk = range.chunkSize {
            points = groupAndAverage(samples: withTemp, chunkSize: chunk)
        } else {
            points = rawPoints(samples: withTemp)
        }

        return AggregationResult(points: points, min: minTemp, max: maxTemp, average: avgTemp, measurementCount: count, gaps: gaps(in: points))
    }

    /// Gap threshold: 3 × the real interval between readings (at least 3 × 30 s).
    /// The real interval is the median of the gaps, which keeps older histories
    /// (one reading every 5 min) readable without splitting them up.
    public static func breakThreshold(for samples: [HistorySample]) -> TimeInterval {
        guard samples.count > 1 else { return 3 * nominalInterval }
        var diffs: [TimeInterval] = []
        diffs.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            diffs.append(samples[i].date.timeIntervalSince(samples[i - 1].date))
        }
        diffs.sort()
        let median = diffs[diffs.count / 2]
        return 3 * Swift.max(nominalInterval, median)
    }

    private static func rawPoints(samples: [HistorySample]) -> [AggregatedPoint] {
        let threshold = breakThreshold(for: samples)
        var points: [AggregatedPoint] = []
        var currentSegment = 0
        for i in 0..<samples.count {
            let sample = samples[i]
            guard let temp = sample.temperatureC else { continue }
            if i > 0 && sample.date.timeIntervalSince(samples[i - 1].date) > threshold {
                currentSegment += 1
            }
            points.append(AggregatedPoint(
                date: sample.date,
                temperature: Double(temp),
                segment: currentSegment,
                minTemperature: sample.temperatureMinC.map(Double.init),
                maxTemperature: sample.temperatureMaxC.map(Double.init)
            ))
        }
        return points
    }

    private static func gaps(in points: [AggregatedPoint]) -> [DateInterval] {
        guard points.count > 1 else { return [] }
        var result: [DateInterval] = []
        for i in 1..<points.count where points[i].segment != points[i - 1].segment {
            let start = points[i - 1].date
            let end = points[i].date
            if end > start { result.append(DateInterval(start: start, end: end)) }
        }
        return result
    }

    /// Groups readings into buckets aligned on the clock (multiples of `chunkSize`):
    /// the buckets don't move from one reload to the next, so the curve doesn't “shake”
    /// every 30 s as the window slides.
    private static func groupAndAverage(samples: [HistorySample], chunkSize: TimeInterval) -> [AggregatedPoint] {
        var points: [AggregatedPoint] = []
        var chunk: [HistorySample] = []
        var chunkStart: TimeInterval = -1
        var currentSegment = 0
        var lastChunkStart: TimeInterval? = nil

        func closeChunk() {
            guard !chunk.isEmpty else { return }
            var sum = 0.0
            var weight = 0
            var lo = Double.greatestFiniteMagnitude
            var hi = -Double.greatestFiniteMagnitude
            for s in chunk {
                guard let temperature = s.temperatureC else { continue }
                let t = Double(temperature)
                sum += t * Double(s.measurementCount)
                weight += s.measurementCount
                lo = Swift.min(lo, s.temperatureMinC.map(Double.init) ?? t)
                hi = Swift.max(hi, s.temperatureMaxC.map(Double.init) ?? t)
            }
            guard weight > 0 else { return }
            if let lastStart = lastChunkStart, chunkStart - lastStart > 3 * chunkSize {
                currentSegment += 1
            }
            // Point placed in the middle of its bucket.
            points.append(AggregatedPoint(date: Date(timeIntervalSince1970: chunkStart + chunkSize / 2), temperature: sum / Double(weight), segment: currentSegment, minTemperature: lo, maxTemperature: hi))
            lastChunkStart = chunkStart
        }

        for sample in samples {
            let start = floor(sample.date.timeIntervalSince1970 / chunkSize) * chunkSize
            if start != chunkStart {
                closeChunk()
                chunk = []
                chunkStart = start
            }
            chunk.append(sample)
        }
        closeChunk()

        return points
    }
}
