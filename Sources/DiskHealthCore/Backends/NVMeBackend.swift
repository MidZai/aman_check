import Foundation

public struct NVMeBackend: HealthBackend {
    public static func canHandle(bsdName: String) -> Bool {
        let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
        return protocolType == .nvme
    }
    
    public static func read(bsdName: String) throws -> DiskHealthSnapshot {
        try read(bsdName: bsdName, knownIdentify: nil)
    }

    /// `knownIdentify`: Identify data from a previous read. It doesn't change
    /// (model, serial number, thresholds), so only the SMART log is read again.
    public static func read(bsdName: String, knownIdentify: NVMeIdentify?) throws -> DiskHealthSnapshot {
        if let identify = knownIdentify {
            guard let smartLog = NVMeSmartParser.parse(try NVMeReader.readSmartLog(bsdName: bsdName)) else {
                throw NVMeReadError.readFailed
            }
            return .nvme(smartLog, identify)
        }
        let raw = try NVMeReader.readAll(bsdName: bsdName)
        guard let smartLog = NVMeSmartParser.parse(raw.smart),
              let identify = NVMeIdentifyParser.parse(raw.identify) else {
            throw NVMeReadError.readFailed
        }
        return .nvme(smartLog, identify)
    }
}
