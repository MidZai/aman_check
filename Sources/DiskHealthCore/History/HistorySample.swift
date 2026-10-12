import Foundation

public struct HistorySample: Codable, Hashable {
    public let date: Date
    /// Measured temperature; for a compacted sample, the rounded average of the bucket.
    public let temperatureC: Int?
    public let percentageUsed: Int?
    public let dataUnitsWritten: UInt64?
    public let dataUnitsRead: UInt64?
    public let powerOnHours: UInt64?
    public let mediaErrors: UInt64?
    public let availableSpare: Int?
    // v0.9: only present on compacted samples (5-minute buckets).
    // Optional, so older history files can be read without conversion.
    public let temperatureMinC: Int?
    public let temperatureMaxC: Int?
    /// Number of real readings represented by this sample (nil = 1).
    public let sampleCount: Int?

    public init(date: Date, temperatureC: Int?, percentageUsed: Int?, dataUnitsWritten: UInt64?, dataUnitsRead: UInt64?, powerOnHours: UInt64?, mediaErrors: UInt64?, availableSpare: Int?, temperatureMinC: Int? = nil, temperatureMaxC: Int? = nil, sampleCount: Int? = nil) {
        self.date = date
        self.temperatureC = temperatureC
        self.percentageUsed = percentageUsed
        self.dataUnitsWritten = dataUnitsWritten
        self.dataUnitsRead = dataUnitsRead
        self.powerOnHours = powerOnHours
        self.mediaErrors = mediaErrors
        self.availableSpare = availableSpare
        self.temperatureMinC = temperatureMinC
        self.temperatureMaxC = temperatureMaxC
        self.sampleCount = sampleCount
    }

    public var measurementCount: Int { sampleCount ?? 1 }
    public var isCompacted: Bool { sampleCount != nil }
}

extension HistorySample {
    /// Converts a health reading into a history sample.
    /// ATA: amounts written and read are stored in bytes; the readable conversion happens at display time.
    public static func from(snapshot: DiskHealthSnapshot, date: Date = Date()) -> HistorySample {
        let m = DiskMetrics(snapshot: snapshot)
        switch snapshot {
        case .nvme(let smartLog, _):
            return HistorySample(
                date: date,
                temperatureC: m.temperatureC,
                percentageUsed: m.percentageUsed,
                dataUnitsWritten: smartLog.dataUnitsWritten,
                dataUnitsRead: smartLog.dataUnitsRead,
                powerOnHours: m.powerOnHours,
                mediaErrors: m.mediaErrors,
                availableSpare: m.availableSparePercent
            )
        case .ata:
            return HistorySample(date: date, temperatureC: m.temperatureC, percentageUsed: m.percentageUsed, dataUnitsWritten: m.bytesWritten, dataUnitsRead: m.bytesRead, powerOnHours: m.powerOnHours, mediaErrors: m.badSectors, availableSpare: nil)
        }
    }
}

extension DiskIdentity {
    /// History key of a drive, derived from the model and the serial number.
    public static func key(for snapshot: DiskHealthSnapshot) -> String {
        switch snapshot {
        case .nvme(_, let id): return key(model: id.modelNumber, serial: id.serialNumber)
        case .ata(let ata): return key(model: ata.model, serial: ata.serialNumber)
        }
    }
}
