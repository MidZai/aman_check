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
