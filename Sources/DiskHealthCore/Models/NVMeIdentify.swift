import Foundation

public struct NVMeIdentify: Codable, Equatable, Hashable {
    public let serialNumber: String
    public let modelNumber: String
    public let firmwareRevision: String
    public let warningTempKelvin: UInt16
    public let criticalTempKelvin: UInt16
    public let totalCapacityBytes: UInt64
    
    public init(serialNumber: String, modelNumber: String, firmwareRevision: String, warningTempKelvin: UInt16, criticalTempKelvin: UInt16, totalCapacityBytes: UInt64) {
        self.serialNumber = serialNumber
        self.modelNumber = modelNumber
        self.firmwareRevision = firmwareRevision
        self.warningTempKelvin = warningTempKelvin
        self.criticalTempKelvin = criticalTempKelvin
        self.totalCapacityBytes = totalCapacityBytes
    }
}
