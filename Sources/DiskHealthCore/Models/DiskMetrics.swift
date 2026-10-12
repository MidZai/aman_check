import Foundation

/// Key indicators of a reading, extracted once whatever the protocol.
/// Single source for the tiles, the menu bar panel, the reports and the history:
/// before, each view did this extraction its own way and the numbers could differ.
public struct DiskMetrics: Equatable, Codable {
    public let temperatureC: Int?
    public let powerOnHours: UInt64?
    public let powerCycles: UInt64?
    public let unsafeShutdowns: UInt64?
    public let bytesWritten: UInt64?
    public let bytesRead: UInt64?
    /// Remaining life reported by the drive (100 − “percentage used” on NVMe).
    public let lifeRemainingPercent: Int?
    /// Endurance used, as reported by the drive; can exceed 100% on NVMe.
    public let percentageUsed: Int?
    public let availableSparePercent: Int?
    /// NVMe: uncorrected data errors (“Media and Data Integrity Errors”).
    public let mediaErrors: UInt64?
    /// ATA: reallocated sectors + sectors pending reallocation.
    public let badSectors: UInt64?

    /// ATA attribute identifiers that can carry the remaining-life role, most trustworthy first.
    static let lifeAttributePriority: [UInt8] = [0xE7, 0xB1, 0xE9]

    public init(snapshot: DiskHealthSnapshot) {
        switch snapshot {
        case .nvme(let log, _):
            temperatureC = log.temperatureCelsius
            powerOnHours = log.powerOnHours
            powerCycles = log.powerCycles
            unsafeShutdowns = log.unsafeShutdowns
            bytesWritten = Formatters.dataUnitsToBytes(log.dataUnitsWritten)
            bytesRead = Formatters.dataUnitsToBytes(log.dataUnitsRead)
            percentageUsed = Int(log.percentageUsed)
            lifeRemainingPercent = max(0, 100 - Int(log.percentageUsed))
            availableSparePercent = Int(log.availableSpare)
            mediaErrors = log.mediaErrors
            badSectors = nil

        case .ata(let ata):
            let profile = ATACatalog.profile(for: ata.model)
            var temperature: Int?
            var temperatureIsPrimary = false
            var hours: UInt64?
            var cycles: UInt64?
            var unsafe: UInt64?
            var written: UInt64?
            var read: UInt64?
            var life: Int?
            var lifeRank = Int.max
            var sectors: UInt64?
            // Remaining life is meaningless on a hard drive with platters (rotation rate in rpm).
            let isRotational = ata.rotationRate > 1
            for attr in ata.attributes {
                let role = ATACatalog.attributeInfo(id: attr.id, profile: profile).role
                switch role {
                case .temperature:
                    // 0xC2 (194) is the drive temperature; 0xBE (190) is the airflow temperature.
                    guard let t = attr.value(for: role) else { break }
                    if attr.id == 0xC2 || !temperatureIsPrimary {
                        temperature = Int(t)
                        temperatureIsPrimary = attr.id == 0xC2
                    }
                case .powerOnHours: hours = attr.value(for: role)
                case .powerCycles: cycles = attr.value(for: role)
                case .unsafeShutdowns: unsafe = attr.value(for: role)
                case .hostWritesBytes: written = attr.value(for: role)
                case .hostReadsBytes: read = attr.value(for: role)
                case .lifeRemainingPercentNormalized:
                    // Several attributes can carry this role. Fixed priority: 231 (0xE7, SSD life left)
                    // first, then 177 (0xB1) when the profile declares it, then 233 (0xE9, media wearout),
                    // which is a wear indicator only on some drives. A lower priority never overwrites
                    // a higher one already read.
                    guard !isRotational, let rank = Self.lifeAttributePriority.firstIndex(of: attr.id), rank < lifeRank else { break }
                    lifeRank = rank
                    life = max(0, min(100, Int(attr.current)))
                case .reallocated, .pending:
                    let (sum, overflow) = (sectors ?? 0).addingReportingOverflow(attr.rawValue)
                    sectors = overflow ? UInt64.max : sum
                case .uncorrectable, .none: break
                }
            }
            temperatureC = temperature
            powerOnHours = hours
            powerCycles = cycles
            unsafeShutdowns = unsafe
            bytesWritten = written
            bytesRead = read
            lifeRemainingPercent = life
            percentageUsed = life.map { 100 - $0 }
            availableSparePercent = nil
            mediaErrors = nil
            badSectors = sectors
        }
    }
}
