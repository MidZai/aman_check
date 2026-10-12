import Foundation

public enum Connection: String, Codable {
    case nvmeInternal, nvmeExternal, usb, sata, other
}

public struct PhysicalDisk: Codable, Identifiable, Hashable {
    public var id: String { bsdName }
    public let bsdName: String
    public let model: String
    public let sizeBytes: UInt64
    public let isInternal: Bool
    public var isExternal: Bool { !isInternal }
    public let connection: Connection
    public let driveConnection: DriveConnection
    public let volumeNames: [String]
    public let usbVendorID: UInt16?     // only if connection == .usb
    public let usbProductID: UInt16?
    public let usbVendorName: String?
    public let usbProductName: String?
    public let usbLinkSpeedBps: UInt64?
    public let usbBcdUSB: UInt16?
    public let usbIsUAS: Bool?
    public let protocolType: StorageProtocol
    public let mediumType: MediumType
    public let healthCapability: HealthCapability
    public let smartAvailability: SmartAvailability?
    public let serialNumber: String?
    public let isVirtual: Bool
    public let isDiskImage: Bool

    public init(
        bsdName: String,
        model: String,
        sizeBytes: UInt64,
        isInternal: Bool,
        connection: Connection,
        driveConnection: DriveConnection? = nil,
        volumeNames: [String],
        usbVendorID: UInt16? = nil,
        usbProductID: UInt16? = nil,
        usbVendorName: String? = nil,
        usbProductName: String? = nil,
        usbLinkSpeedBps: UInt64? = nil,
        usbBcdUSB: UInt16? = nil,
        usbIsUAS: Bool? = nil,
        protocolType: StorageProtocol,
        mediumType: MediumType,
        healthCapability: HealthCapability,
        smartAvailability: SmartAvailability? = nil,
        serialNumber: String? = nil,
        isVirtual: Bool = false,
        isDiskImage: Bool = false
    ) {
        self.bsdName = bsdName
        self.model = model
        self.sizeBytes = sizeBytes
        self.isInternal = isInternal
        self.connection = connection
        self.serialNumber = serialNumber
        if let dc = driveConnection {
            self.driveConnection = dc
        } else {
            switch connection {
            case .nvmeInternal: self.driveConnection = .internalNVMe
            case .nvmeExternal: self.driveConnection = .thunderboltNVMe
            case .usb:          self.driveConnection = .usb
            case .sata:         self.driveConnection = isInternal ? .internalSATA : .other("SATA")
            case .other:
                if protocolType == .pcieAhci && isInternal {
                    self.driveConnection = .internalAHCI
                } else {
                    self.driveConnection = .other(isInternal ? "Internal" : "Other")
                }
            }
        }
        self.volumeNames = volumeNames
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.usbVendorName = usbVendorName
        self.usbProductName = usbProductName
        self.usbLinkSpeedBps = usbLinkSpeedBps
        self.usbBcdUSB = usbBcdUSB
        self.usbIsUAS = usbIsUAS
        self.protocolType = protocolType
        self.mediumType = mediumType
        self.healthCapability = healthCapability
        self.smartAvailability = smartAvailability
        self.isVirtual = isVirtual
        self.isDiskImage = isDiskImage
    }

    /// Convenience initializer when initialized with `driveConnection`.
    public init(
        bsdName: String,
        model: String,
        sizeBytes: UInt64,
        isInternal: Bool,
        driveConnection: DriveConnection,
        volumeNames: [String],
        usbVendorID: UInt16? = nil,
        usbProductID: UInt16? = nil,
        usbVendorName: String? = nil,
        usbProductName: String? = nil,
        usbLinkSpeedBps: UInt64? = nil,
        usbBcdUSB: UInt16? = nil,
        usbIsUAS: Bool? = nil,
        protocolType: StorageProtocol,
        mediumType: MediumType,
        healthCapability: HealthCapability,
        smartAvailability: SmartAvailability? = nil,
        serialNumber: String? = nil,
        isVirtual: Bool = false,
        isDiskImage: Bool = false
    ) {
        let conn: Connection
        switch driveConnection {
        case .internalNVMe: conn = .nvmeInternal
        case .internalAHCI: conn = .other
        case .internalSATA: conn = .sata
        case .thunderboltNVMe: conn = .nvmeExternal
        case .usb: conn = .usb
        case .other: conn = .other
        }
        self.init(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: conn,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            usbVendorName: usbVendorName,
            usbProductName: usbProductName,
            usbLinkSpeedBps: usbLinkSpeedBps,
            usbBcdUSB: usbBcdUSB,
            usbIsUAS: usbIsUAS,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: healthCapability,
            smartAvailability: smartAvailability,
            serialNumber: serialNumber,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }

    // Custom Decodable so older JSON without isVirtual/isDiskImage/driveConnection can still be decoded.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bsdName         = try c.decode(String.self, forKey: .bsdName)
        model           = try c.decode(String.self, forKey: .model)
        sizeBytes       = try c.decode(UInt64.self, forKey: .sizeBytes)
        isInternal      = try c.decode(Bool.self, forKey: .isInternal)
        let decodedConn = try c.decode(Connection.self, forKey: .connection)
        connection      = decodedConn
        volumeNames     = try c.decode([String].self, forKey: .volumeNames)
        usbVendorID     = try c.decodeIfPresent(UInt16.self, forKey: .usbVendorID)
        usbProductID    = try c.decodeIfPresent(UInt16.self, forKey: .usbProductID)
        usbVendorName   = try c.decodeIfPresent(String.self, forKey: .usbVendorName)
        usbProductName  = try c.decodeIfPresent(String.self, forKey: .usbProductName)
        usbLinkSpeedBps = try c.decodeIfPresent(UInt64.self, forKey: .usbLinkSpeedBps)
        usbBcdUSB       = try c.decodeIfPresent(UInt16.self, forKey: .usbBcdUSB)
        usbIsUAS        = try c.decodeIfPresent(Bool.self, forKey: .usbIsUAS)
        protocolType    = try c.decode(StorageProtocol.self, forKey: .protocolType)
        mediumType      = try c.decode(MediumType.self, forKey: .mediumType)
        healthCapability = try c.decode(HealthCapability.self, forKey: .healthCapability)
        smartAvailability = try c.decodeIfPresent(SmartAvailability.self, forKey: .smartAvailability)
        serialNumber    = try c.decodeIfPresent(String.self, forKey: .serialNumber)
        isVirtual       = try c.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        isDiskImage     = try c.decodeIfPresent(Bool.self, forKey: .isDiskImage) ?? false

        if let dc = try c.decodeIfPresent(DriveConnection.self, forKey: .driveConnection) {
            driveConnection = dc
        } else {
            switch decodedConn {
            case .nvmeInternal: driveConnection = .internalNVMe
            case .nvmeExternal: driveConnection = .thunderboltNVMe
            case .usb:          driveConnection = .usb
            case .sata:         driveConnection = isInternal ? .internalSATA : .other("SATA")
            case .other:
                if protocolType == .pcieAhci && isInternal {
                    driveConnection = .internalAHCI
                } else {
                    driveConnection = .other(isInternal ? "Internal" : "Other")
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bsdName, model, sizeBytes, isInternal, connection, driveConnection, volumeNames
        case usbVendorID, usbProductID, usbVendorName, usbProductName, usbLinkSpeedBps, usbBcdUSB, usbIsUAS
        case protocolType, mediumType, healthCapability, smartAvailability, serialNumber
        case isVirtual, isDiskImage
    }

    public func withCapability(_ capability: HealthCapability) -> PhysicalDisk {
        PhysicalDisk(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: connection,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            usbVendorName: usbVendorName,
            usbProductName: usbProductName,
            usbLinkSpeedBps: usbLinkSpeedBps,
            usbBcdUSB: usbBcdUSB,
            usbIsUAS: usbIsUAS,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: capability,
            smartAvailability: smartAvailability,
            serialNumber: serialNumber,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }

    public func withSmartAvailability(_ availability: SmartAvailability) -> PhysicalDisk {
        PhysicalDisk(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: connection,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            usbVendorName: usbVendorName,
            usbProductName: usbProductName,
            usbLinkSpeedBps: usbLinkSpeedBps,
            usbBcdUSB: usbBcdUSB,
            usbIsUAS: usbIsUAS,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: healthCapability,
            smartAvailability: availability,
            serialNumber: serialNumber,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }

    public var isThunderbolt: Bool {
        driveConnection == .thunderboltNVMe
    }

    /// Whether this drive is an external USB drive using SAT (SCSI / ATA Translation) via the SAT SMART Driver.
    public var isSATTranslationActive: Bool {
        (driveConnection == .usb || connection == .usb) && (protocolType == .ata || protocolType == .pcieAhci)
    }

    /// Formatted USB Bridge Chip string (e.g. "Realtek (0x0BDA)" or "Puce inconnue (0x1234)")
    public var usbBridgeLabel: String? {
        guard let vid = usbVendorID else { return nil }
        let hexStr = String(format: "0x%04X", vid)
        if let vendor = USBBridgeDatabase.shared.vendorName(for: vid) ?? usbVendorName, !vendor.isEmpty {
            return "\(vendor) (\(hexStr))"
        }
        return L("Unknown chip (\(hexStr))", "Puce inconnue (\(hexStr))")
    }

    /// Formatted USB link speed (e.g. "USB 3.2 Gen 2 — 10 Gb/s", "USB 3.0 — 5 Gb/s", "USB 2.0 — 480 Mb/s")
    public var usbLinkSpeedLabel: String? {
        guard driveConnection == .usb || protocolType == .usb else { return nil }
        if let bps = usbLinkSpeedBps {
            if bps >= 36_000_000_000 {
                return "USB4 — 40\(Formatters.unitSpace)Gb/s"
            } else if bps >= 18_000_000_000 {
                return "USB 3.2 Gen 2x2 — 20\(Formatters.unitSpace)Gb/s"
            } else if bps >= 9_000_000_000 {
                return "USB 3.2 Gen 2 — 10\(Formatters.unitSpace)Gb/s"
            } else if bps >= 4_500_000_000 {
                return "USB 3.0 — 5\(Formatters.unitSpace)Gb/s"
            } else if bps >= 400_000_000 {
                return "USB 2.0 — 480\(Formatters.unitSpace)Mb/s"
            } else if bps >= 10_000_000 {
                return "USB 1.1 — 12\(Formatters.unitSpace)Mb/s"
            }
        }
        if let bcd = usbBcdUSB {
            if bcd >= 0x0320 { return "USB 3.2" }
            if bcd >= 0x0310 { return "USB 3.1" }
            if bcd >= 0x0300 { return "USB 3.0" }
            if bcd >= 0x0200 { return "USB 2.0" }
            if bcd >= 0x0110 { return "USB 1.1" }
        }
        return nil
    }

    /// Formatted USB protocol label (e.g. "UAS" or "BOT")
    public var usbProtocolLabel: String? {
        guard driveConnection == .usb || protocolType == .usb else { return nil }
        if let isUAS = usbIsUAS {
            return isUAS ? "UAS (USB Attached SCSI)" : "BOT (Bulk-Only Transport)"
        }
        return nil
    }

    /// Detailed connection type for disk details: e.g. “Thunderbolt / USB4 (PCIe)” or “USB (SATA via SAT)”
    public var detailInterfaceLabel: String {
        if driveConnection == .thunderboltNVMe {
            return "Thunderbolt / USB4 (PCIe)"
        }
        if isSATTranslationActive {
            return "USB (SATA via SAT)"
        }
        switch protocolType {
        case .nvme: return "NVMe"
        case .pcieAhci: return "PCIe AHCI"
        case .ata: return "SATA"
        case .usb: return "USB"
        case .sdCard: return "SD Card"
        case .virtualDisk: return "Virtual"
        case .unknown:
            switch driveConnection {
            case .internalNVMe, .thunderboltNVMe: return "NVMe"
            case .internalAHCI: return "PCIe AHCI"
            case .internalSATA: return "SATA"
            case .usb: return "USB"
            case .other(let name): return name.isEmpty ? "Other" : name
            }
        }
    }
}
