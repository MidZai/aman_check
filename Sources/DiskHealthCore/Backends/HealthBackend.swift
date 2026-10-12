import Foundation

public enum StorageProtocol: String, Codable, Hashable {
    case nvme, ata, pcieAhci, sdCard, virtualDisk, usb, unknown
}

public enum MediumType: String, Codable, Hashable {
    case solidState, rotational, unknown
}

public enum HealthCapability: Codable, Equatable, Hashable {
    case supported
    case unsupported(reason: UnsupportedReason)
}

public enum UnsupportedReason: Codable, Equatable, Hashable {
    case usbBridge
    case sdCardReader
    case virtualDisk
    case smartDisabled
    case noSmartInterface
    case readFailed(code: String)
    
    public var rawValue: String {
        switch self {
        case .usbBridge: return "usbBridge"
        case .sdCardReader: return "sdCardReader"
        case .virtualDisk: return "virtualDisk"
        case .smartDisabled: return "smartDisabled"
        case .noSmartInterface: return "noSmartInterface"
        case .readFailed(let code): return "readFailed(\(code))"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, code
    }
    
    public init(from decoder: Decoder) throws {
        // Try the legacy single-value format first for backwards compatibility,
        // then fall back to the canonical keyed format.
        if let singleContainer = try? decoder.singleValueContainer(),
           let str = try? singleContainer.decode(String.self) {
            switch str {
            case "usbBridge":         self = .usbBridge; return
            case "sdCardReader":      self = .sdCardReader; return
            case "virtualDisk":       self = .virtualDisk; return
            case "smartDisabled":     self = .smartDisabled; return
            case "noSmartInterface":  self = .noSmartInterface; return
            case "readFailed":        self = .readFailed(code: "unknown"); return
            default: break
            }
        }
        // Canonical keyed format.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "usbBridge":        self = .usbBridge
        case "sdCardReader":     self = .sdCardReader
        case "virtualDisk":      self = .virtualDisk
        case "smartDisabled":    self = .smartDisabled
        case "noSmartInterface": self = .noSmartInterface
        case "readFailed":
            let code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
            self = .readFailed(code: code)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown UnsupportedReason type: \(type)")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        // Always use a keyed container for a stable, unambiguous format.
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .usbBridge:
            try container.encode("usbBridge", forKey: .type)
        case .sdCardReader:
            try container.encode("sdCardReader", forKey: .type)
        case .virtualDisk:
            try container.encode("virtualDisk", forKey: .type)
        case .smartDisabled:
            try container.encode("smartDisabled", forKey: .type)
        case .noSmartInterface:
            try container.encode("noSmartInterface", forKey: .type)
        case .readFailed(let code):
            try container.encode("readFailed", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }

}

public protocol HealthBackend {
    static func canHandle(bsdName: String) -> Bool
    static func read(bsdName: String) throws -> DiskHealthSnapshot
}
