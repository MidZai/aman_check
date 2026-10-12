import Foundation
import CDiskIO

public enum NVMeReadError: Error {
    case notFound
    case notNVMe
    case pluginFailed
    case readFailed
    case bufferTooSmall
    case unknown(Int32)
}

public enum NVMeReader {
    private static func mapError(_ code: Int32) -> NVMeReadError {
        switch code {
        case -1: return .notFound
        case -2: return .notNVMe
        case -3: return .pluginFailed
        case -4: return .readFailed
        case -5: return .bufferTooSmall
        default: return .unknown(code)
        }
    }

    /// SMART log (512 bytes) and Identify (4096 bytes), opening the driver only once.
    public static func readAll(bsdName: String) throws -> (smart: Data, identify: Data) {
        var smart = [UInt8](repeating: 0, count: 512)
        var identify = [UInt8](repeating: 0, count: 4096)
        let result = bsdName.withCString { bsdNameC in
            cdiskio_read_nvme_all(bsdNameC, &smart, &identify)
        }
        guard result == 0 else { throw mapError(result) }
        return (Data(smart), Data(identify))
    }

    public static func readSmartLog(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { bsdNameC in
            cdiskio_read_nvme_smart(bsdNameC, &buffer, 512)
        }
        if result == 0 {
            return Data(buffer)
        }
        throw mapError(result)
    }

    public static func readIdentify(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let result = bsdName.withCString { bsdNameC in
            cdiskio_read_nvme_identify(bsdNameC, &buffer, 4096)
        }
        if result == 0 {
            return Data(buffer)
        }
        throw mapError(result)
    }
}
