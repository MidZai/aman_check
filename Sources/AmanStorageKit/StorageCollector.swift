import Foundation
import AmanCore
import DiskHealthCore

/// `Foundation.Measurement` existe aussi : la mesure d'Aman Check l'emporte dans ce module.
typealias Measurement = AmanCore.Measurement

/// Lecture du SSD interne avec le moteur d'Aman Disk (DiskHealthCore), convertie en mesures.
/// Mêmes règles de lecture qu'Aman Disk (AppManager.read) : NVMe, ou ATA/AHCI sans activation automatique
/// de S.M.A.R.T. (Aman Check ne modifie jamais le disque).
public enum StorageCollector {
    public struct Reading {
        public let disk: PhysicalDisk
        public let snapshot: DiskHealthSnapshot?
        public let health: HealthAssessment?
        public let error: String?
        /// Autres disques internes, non décrits par le rapport.
        public var otherInternalDisks: [PhysicalDisk] = []
    }

    /// Le disque physique qui porte le volume de démarrage (« / »), via la résolution IOKit du moteur ;
    /// à défaut le premier NVMe, puis le premier disque. Les autres disques internes sont renvoyés à part.
    static func bootDisk(among disks: [PhysicalDisk], volumes: [Volume]) -> (disk: PhysicalDisk, others: [PhysicalDisk])? {
        let rootNames = volumes.first(where: { $0.mountPoint == "/" })?.physicalDiskBSDNames ?? []
        guard let disk = disks.first(where: { rootNames.contains($0.bsdName) })
            ?? disks.first(where: { $0.protocolType == .nvme })
            ?? disks.first else { return nil }
        return (disk, disks.filter { $0.bsdName != disk.bsdName })
    }

    /// Disque interne qui porte le volume de démarrage (ou, à défaut, le premier disque interne).
    public static func readInternalDisk() -> Reading? {
        let disks = DiskDiscovery.listPhysicalDisks().filter { $0.isInternal && !$0.isVirtual && !$0.isDiskImage }
        guard let (disk, others) = bootDisk(among: disks, volumes: VolumeDiscovery.listVolumes()) else { return nil }
        guard disk.healthCapability == .supported else {
            return Reading(disk: disk, snapshot: nil, health: nil, error: "healthCapability: \(disk.healthCapability)", otherInternalDisks: others)
        }
        do {
            let snapshot: DiskHealthSnapshot
            switch disk.protocolType {
            case .nvme: snapshot = try NVMeBackend.read(bsdName: disk.bsdName)
            case .ata, .pcieAhci: snapshot = try ATABackend.read(bsdName: disk.bsdName)
            default:
                return Reading(disk: disk, snapshot: nil, health: nil, error: "protocol: \(disk.protocolType.rawValue)", otherInternalDisks: others)
            }
            return Reading(disk: disk, snapshot: snapshot, health: evaluate(snapshot), error: nil, otherInternalDisks: others)
        } catch {
            return Reading(disk: disk, snapshot: nil, health: nil, error: "\(error)", otherInternalDisks: others)
        }
    }

    /// « SSD health » / « SSD wear » deviennent « État du disque » / « Usure du disque » sur un disque à plateaux.
    static func healthTitle(_ disk: PhysicalDisk) -> String? {
        disk.mediumType == .rotational ? L("Drive health", "État du disque") : nil
    }
    static func wearTitle(_ disk: PhysicalDisk) -> String? {
        disk.mediumType == .rotational ? L("Drive wear", "Usure du disque") : nil
    }

    static func evaluate(_ snapshot: DiskHealthSnapshot) -> HealthAssessment {
        switch snapshot {
        case .nvme(let log, let identify): return HealthEngine.evaluate(smart: log, identify: identify)
        case .ata(let ata): return ATAHealthEvaluator.evaluate(snapshot: ata)
        }
    }

    /// Capacité du disque interne, affichée dans la configuration (« 500,3 Go »), comme Aman Disk.
    public static func capacityMeasurement(_ reading: Reading?, now: Date = Date()) -> AmanCore.Measurement {
        guard let disk = reading?.disk, disk.sizeBytes > 0 else {
            return .unavailable(MetricID.storageCapacity, note: L("No internal drive found.", "Aucun disque interne détecté."))
        }
        return Measurement(id: MetricID.storageCapacity, value: .int(Int64(clamping: disk.sizeBytes)), unit: "B", status: .info,
                           method: "IOKit · IOMedia Size", collectedAt: now, display: Formatters.bytes(disk.sizeBytes),
                           detail: interfaceLabel(disk))
    }

    public static func measurements(_ reading: Reading?, now: Date = Date()) -> [AmanCore.Measurement] {
        let notReported = L("Not reported by this SSD.", "Non fourni par ce SSD.")
        guard let reading else {
            return [.unavailable(MetricID.storageHealth, note: L("No internal drive found.", "Aucun disque interne détecté."))]
        }
        var result: [Measurement] = []
        let disk = reading.disk
        let othersNote: String? = reading.otherInternalDisks.isEmpty ? nil
            : L("Other internal drives: \(reading.otherInternalDisks.map(\.model).joined(separator: ", "))",
                "Autres disques internes : \(reading.otherInternalDisks.map(\.model).joined(separator: ", "))")
        result.append(Measurement(id: MetricID.storageModel, value: .text(disk.model), status: .info,
                                  method: "IOKit", collectedAt: now, display: disk.model, note: othersNote))
        result.append(Measurement(id: MetricID.storageInterface, value: .text(interfaceLabel(disk)), status: .info,
                                  method: "IOKit", collectedAt: now, display: interfaceLabel(disk)))

        guard let snapshot = reading.snapshot, let health = reading.health else {
            let note = L("This SSD does not expose its health data (S.M.A.R.T.) to macOS.",
                         "Ce SSD ne fournit pas ses données de santé (S.M.A.R.T.) à macOS.")
            result.insert(Measurement(id: MetricID.storageHealth, value: nil, status: .unavailable,
                                      method: reading.error, collectedAt: now, note: note, title: healthTitle(disk)), at: 0)
            for id in [MetricID.storagePowerOnHours, MetricID.storageDataWritten, MetricID.storagePercentageUsed] {
                result.append(.unavailable(id, note: note))
            }
            return result
        }

        let metrics = DiskMetrics(snapshot: snapshot)
        let protocolName: String = { if case .nvme = snapshot { return "NVMe SMART / Health log" } else { return "ATA S.M.A.R.T." } }()

        // Verdict d'Aman Disk, tel quel (mêmes seuils, mêmes raisons).
        let status: CheckStatus
        let statusText: String
        switch health.status {
        case .good: (status, statusText) = (.good, L("Healthy", "En bonne santé"))
        case .caution: (status, statusText) = (.watch, L("Needs attention", "À surveiller"))
        case .bad: (status, statusText) = (.problem, L("Likely failing", "Défaillance probable"))
        case .unknown: (status, statusText) = (.unavailable, L("Unknown", "Inconnu"))
        }
        result.insert(Measurement(id: MetricID.storageHealth, value: .text(health.status.rawValue), status: status,
                                  method: protocolName + " · Aman Disk HealthEngine", collectedAt: now, display: statusText,
                                  detail: health.reasons.first, note: health.reasons.count > 1 ? health.reasons.joined(separator: " ") : nil,
                                  title: healthTitle(disk)), at: 0)

        // Données vides ou non vérifiées (statut inconnu du moteur) : rien n'est lisible, donc rien n'est vert.
        if health.status == .unknown {
            let note = health.reasons.first ?? notReported
            for id in [MetricID.storagePowerOnHours, MetricID.storageDataWritten, MetricID.storagePercentageUsed] {
                result.append(.unavailable(id, note: note))
            }
            return result
        }

        if let hours = metrics.powerOnHours {
            result.append(Measurement(id: MetricID.storagePowerOnHours, value: .int(Int64(clamping: hours)), unit: "h", status: .info,
                                      method: protocolName + " · Power On Hours", collectedAt: now, display: Formatters.hours(hours),
                                      detail: L("≈ \(Formatters.approximateDuration(hours: hours)) powered on", "≈ \(Formatters.approximateDuration(hours: hours)) sous tension")))
        } else {
            result.append(.unavailable(MetricID.storagePowerOnHours, note: notReported))
        }

        if let written = metrics.bytesWritten {
            result.append(Measurement(id: MetricID.storageDataWritten, value: .int(Int64(clamping: written)), unit: "B", status: .info,
                                      method: protocolName + (metrics.bytesRead != nil ? " · Data Units Written × 512 000" : ""),
                                      collectedAt: now, display: Formatters.bytes(written),
                                      detail: metrics.bytesRead.map { L("Read: \(Formatters.bytes($0))", "Lues : \(Formatters.bytes($0))") }))
        } else {
            result.append(.unavailable(MetricID.storageDataWritten, note: notReported))
        }

        if let used = metrics.percentageUsed {
            // Même seuil que l'anneau d'Aman Disk : durée de vie restante ≤ 25 % → à surveiller.
            let remaining = max(0, 100 - used)
            let wearStatus: CheckStatus = remaining <= HealthEngine.lowLifeThreshold ? .watch : .good
            result.append(Measurement(id: MetricID.storagePercentageUsed, value: .int(Int64(used)), unit: "%", status: wearStatus,
                                      method: protocolName + " · Percentage Used", collectedAt: now,
                                      display: "\(used)\(Formatters.unitSpace)%",
                                      detail: L("Remaining life: \(remaining)\(Formatters.unitSpace)%", "Durée de vie restante : \(remaining)\(Formatters.unitSpace)%"),
                                      title: wearTitle(disk)))
        } else {
            result.append(Measurement(id: MetricID.storagePercentageUsed, value: nil, status: .unavailable, collectedAt: now,
                                      note: notReported, title: wearTitle(disk)))
        }

        if case .nvme(let log, _) = snapshot {
            let spareStatus: CheckStatus = log.availableSpare < log.availableSpareThreshold ? .problem : .good
            result.append(Measurement(id: MetricID.storageAvailableSpare, value: .int(Int64(log.availableSpare)), unit: "%",
                                      status: spareStatus, method: protocolName + " · Available Spare", collectedAt: now,
                                      display: "\(log.availableSpare)\(Formatters.unitSpace)%",
                                      detail: L("Threshold: \(log.availableSpareThreshold) %", "Seuil : \(log.availableSpareThreshold)\(Formatters.unitSpace)%")))
        }
        if let errors = metrics.mediaErrors {
            result.append(Measurement(id: MetricID.storageMediaErrors, value: .int(Int64(clamping: errors)), status: errors == 0 ? .good : .watch,
                                      method: protocolName + " · Media and Data Integrity Errors", collectedAt: now,
                                      display: Formatters.integer(errors),
                                      detail: errors == 0 ? L("No uncorrected errors", "Aucune erreur non corrigée") : L("Back up your data", "Sauvegardez vos données")))
        } else if let sectors = metrics.badSectors {
            result.append(Measurement(id: MetricID.storageMediaErrors, value: .int(Int64(clamping: sectors)), status: sectors == 0 ? .good : .watch,
                                      method: protocolName + " · 5 + 197", collectedAt: now, display: Formatters.integer(sectors),
                                      detail: sectors == 0 ? L("No sectors replaced", "Aucun secteur remplacé") : L("Reallocated and pending", "Réalloués et en attente")))
        }
        if let temp = metrics.temperatureC {
            result.append(Measurement(id: MetricID.storageTemperature, value: .int(Int64(temp)), unit: "°C", status: .info,
                                      method: protocolName, collectedAt: now, display: Formatters.temperature(temp)))
        }
        return result
    }

    /// « SSD interne · NVMe », comme Aman Disk.
    static func interfaceLabel(_ disk: PhysicalDisk) -> String {
        let medium: String
        switch disk.mediumType {
        case .solidState: medium = "SSD"
        case .rotational: medium = L("Hard drive", "Disque dur")
        case .unknown: medium = L("Disk", "Disque")
        }
        let interface: String
        switch disk.protocolType {
        case .nvme: interface = "NVMe"
        case .pcieAhci: interface = "PCIe AHCI"
        case .ata: interface = "SATA"
        default: interface = disk.detailInterfaceLabel
        }
        return "\(medium) · \(interface)"
    }
}
