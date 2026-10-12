import Foundation

public enum NVMeSmartParser {
    public static func parse(_ data: Data) -> NVMeSmartLog? {
        guard data.count >= 512 else { return nil }
        
        func readU8(_ offset: Int) -> UInt8 {
            return data[offset]
        }
        
        func readU16(_ offset: Int) -> UInt16 {
            let val = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            return UInt16(littleEndian: val)
        }
        
        func readU128AsU64(_ offset: Int) -> UInt64 {
            let lower = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
            let upper = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self) }
            
            let littleLower = UInt64(littleEndian: lower)
            let littleUpper = UInt64(littleEndian: upper)
            
            if littleUpper != 0 {
                return UInt64.max
            }
            return littleLower
        }
        
        return NVMeSmartLog(
            criticalWarning: readU8(0),
            compositeTemperatureKelvin: readU16(1),
            availableSpare: readU8(3),
            availableSpareThreshold: readU8(4),
            percentageUsed: readU8(5),
            dataUnitsRead: readU128AsU64(32),
            dataUnitsWritten: readU128AsU64(48),
            hostReadCommands: readU128AsU64(64),
            hostWriteCommands: readU128AsU64(80),
            controllerBusyTimeMinutes: readU128AsU64(96),
            powerCycles: readU128AsU64(112),
            powerOnHours: readU128AsU64(128),
            unsafeShutdowns: readU128AsU64(144),
            mediaErrors: readU128AsU64(160),
            errorLogEntries: readU128AsU64(176)
        )
    }
}
