import Foundation

public enum DriveConnection: Equatable, Hashable, Codable, Sendable {
    case internalNVMe
    case internalAHCI        // Apple PCIe AHCI
    case internalSATA
    case thunderboltNVMe     // External, PCIe via Thunderbolt/USB4
    case usb                 // External, USB enclosure / flash drive
    case other(String)       // Unknown interconnect, raw text preserved
}

extension DriveConnection {
    public var isExternal: Bool {
        switch self {
        case .internalNVMe, .internalAHCI, .internalSATA:
            return false
        case .thunderboltNVMe, .usb, .other:
            return true
        }
    }

    public var badgeLabel: String {
        switch self {
        case .internalNVMe: return "NVMe"
        case .internalAHCI: return "PCIe AHCI"
        case .internalSATA: return "SATA"
        case .thunderboltNVMe: return "Thunderbolt"
        case .usb: return "USB"
        case .other(let name): return name.isEmpty ? "Other" : name
        }
    }
}
