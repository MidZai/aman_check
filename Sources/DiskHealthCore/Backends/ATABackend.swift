import Foundation

public struct ATABackend: HealthBackend {
    public static func canHandle(bsdName: String) -> Bool {
        let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
        return protocolType == .ata || protocolType == .pcieAhci
    }
    
    public static func read(bsdName: String) throws -> DiskHealthSnapshot {
        let raw = try ATAReader.readAll(bsdName: bsdName)
        guard let snapshot = ATASmartParser.parse(smartData: raw.smart, thresholdsData: raw.thresholds, identifyData: raw.identify, statusExceeded: raw.thresholdExceeded) else {
            throw ATAReadError.parseFailed
        }
        return .ata(snapshot)
    }
}
