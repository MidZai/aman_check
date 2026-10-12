import Foundation
import CDiskIO

public enum ATAReadError: Error, Equatable {
    case invalidArguments
    case diskNotFound
    case mediaNotFound
    case smartServiceNotFound
    case pluginCreationFailed
    case smartDisabled
    case ioError(Int32)
    case unknown(Int32)
    case parseFailed
}

/// Raw data from a full ATA read.
public struct ATARawData {
    public let smart: Data
    public let thresholds: Data
    public let identify: Data
    public let thresholdExceeded: Bool
}

public enum ATAReader {
    private static func mapError(_ code: Int32) -> ATAReadError {
        switch code {
        case -1: return .invalidArguments
        case -2: return .diskNotFound
        case -3: return .mediaNotFound
        case -4: return .smartServiceNotFound
        case -5: return .pluginCreationFailed
        case -6: return .smartDisabled
        default: return .ioError(code)
        }
    }
    
    /// S.M.A.R.T. data, thresholds, Identify and status, opening the driver only once.
    public static func readAll(bsdName: String) throws -> ATARawData {
        var smart = [UInt8](repeating: 0, count: 512)
        var thresholds = [UInt8](repeating: 0, count: 512)
        var identify = [UInt8](repeating: 0, count: 512)
        var exceeded: Int32 = 0
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_snapshot(cString, &smart, &thresholds, &identify, &exceeded)
        }
        guard result == 0 else { throw mapError(result) }
        return ATARawData(smart: Data(smart), thresholds: Data(thresholds), identify: Data(identify), thresholdExceeded: exceeded != 0)
    }

    public static func readSmartData(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_data(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readSmartThresholds(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_thresholds(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readIdentify(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_identify(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readSmartStatus(bsdName: String) throws -> Bool {
        var exceeded: Int32 = 0
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_status(cString, &exceeded)
        }
        
        if result == 0 {
            return exceeded != 0
        } else {
            throw mapError(result)
        }
    }

    /// Turns S.M.A.R.T. on (`SMARTEnableDisableOperations(true)`): the only configuration command
    /// Aman sends to a drive. Never turns it off.
    public static func enableSmart(bsdName: String) throws {
        let result = bsdName.withCString { cdiskio_enable_ata_smart($0) }
        guard result == 0 else { throw mapError(result) }
    }
}
