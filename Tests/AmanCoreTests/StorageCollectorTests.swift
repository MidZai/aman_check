import Testing
import Foundation
@testable import AmanCore
@testable import AmanStorageKit
import DiskHealthCore

@Suite("Stockage")
struct StorageCollectorTests {
    @Test("Un log NVMe vide donne un statut inconnu : aucune ligne de stockage n'est verte")
    func emptyLogIsNeverGood() {
        let log = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 0, availableSpare: 0, availableSpareThreshold: 0,
                               percentageUsed: 0, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0,
                               controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "", modelNumber: "APPLE SSD AP0512N", firmwareRevision: "1", warningTempKelvin: 0,
                                    criticalTempKelvin: 0, totalCapacityBytes: 500_000_000_000)
        let disk = PhysicalDisk(bsdName: "disk0", model: "APPLE SSD AP0512N", sizeBytes: 500_000_000_000, isInternal: true,
                                connection: .nvmeInternal, volumeNames: [], protocolType: .nvme, mediumType: .solidState, healthCapability: .supported)
        let snapshot = DiskHealthSnapshot.nvme(log, identify)
        let reading = StorageCollector.Reading(disk: disk, snapshot: snapshot, health: StorageCollector.evaluate(snapshot), error: nil)
        let measurements = StorageCollector.measurements(reading)
        #expect(measurements.first { $0.id == MetricID.storageHealth }?.status == .unavailable)
        for m in measurements {
            #expect(m.status != .good, "\(m.id) must not be good when the drive answered nothing")
        }
    }
}

extension StorageCollectorTests {
    private static func disk(_ bsd: String, protocolType: StorageProtocol = .nvme, medium: MediumType = .solidState) -> PhysicalDisk {
        PhysicalDisk(bsdName: bsd, model: "Drive \(bsd)", sizeBytes: 1_000_000_000_000, isInternal: true,
                     connection: protocolType == .nvme ? .nvmeInternal : .sata, volumeNames: [], protocolType: protocolType,
                     mediumType: medium, healthCapability: .supported)
    }

    @Test("Le disque décrit est celui qui porte le volume de démarrage, pas le premier NVMe")
    func bootDiskIsPreferred() {
        let nvme = Self.disk("disk0")
        let hdd = Self.disk("disk1", protocolType: .ata, medium: .rotational)
        let root = Volume(bsdName: "disk1s1", name: "Macintosh HD", mountPoint: "/", format: "APFS", totalBytes: 1, availableBytes: 1, physicalDiskBSDNames: ["disk1"])
        let picked = StorageCollector.bootDisk(among: [nvme, hdd], volumes: [root])
        #expect(picked?.disk.bsdName == "disk1")
        #expect(picked?.others.map(\.bsdName) == ["disk0"])
        // Sans volume racine connu : repli sur le NVMe, puis le premier.
        #expect(StorageCollector.bootDisk(among: [hdd, nvme], volumes: [])?.disk.bsdName == "disk0")
    }

    @Test("Disque à plateaux : « État du disque », pas « Santé du SSD », et les autres disques internes sont notés")
    func rotationalDriveLabels() {
        let hdd = Self.disk("disk1", protocolType: .ata, medium: .rotational)
        let attribute = ATASmartAttribute(id: 9, flags: 0, current: 100, worst: 100, threshold: 0, raw: [0, 0, 0, 0, 0, 0], rawValue: 0)
        let ata = ATASmartSnapshot(attributes: [attribute], model: "HDD", firmware: "1", serialNumber: "", rotationRate: 7200,
                                   thresholdExceeded: false, checksumValid: true, thresholdsChecksumValid: true)
        let snapshot = DiskHealthSnapshot.ata(ata)
        let reading = StorageCollector.Reading(disk: hdd, snapshot: snapshot, health: StorageCollector.evaluate(snapshot), error: nil,
                                               otherInternalDisks: [Self.disk("disk0")])
        let measurements = StorageCollector.measurements(reading)
        #expect(measurements.first { $0.id == MetricID.storageHealth }?.label == L("Drive health", "État du disque"))
        #expect(measurements.first { $0.id == MetricID.storagePercentageUsed }?.label == L("Drive wear", "Usure du disque"))
        #expect(measurements.first { $0.id == MetricID.storageModel }?.note?.contains("Drive disk0") == true)
    }
}
