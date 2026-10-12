import Foundation

public enum NVMeIdentifyParser {
    public static func parse(_ data: Data) -> NVMeIdentify? {
        guard data.count >= 4096 else { return nil }
        
        func readString(_ offset: Int, length: Int) -> String {
            let sub = data[offset..<(offset + length)]
            let str = String(decoding: sub, as: UTF8.self)
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        return NVMeIdentify(
            serialNumber: readString(4, length: 20),
            modelNumber: readString(24, length: 40),
            firmwareRevision: readString(64, length: 8),
            warningTempKelvin: readU16(266),
            criticalTempKelvin: readU16(268),
            totalCapacityBytes: readU128AsU64(280)
        )
    }
}
