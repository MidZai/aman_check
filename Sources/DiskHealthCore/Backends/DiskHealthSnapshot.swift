import Foundation

public struct ATASmartAttribute: Codable, Equatable, Hashable, Identifiable {
    public let id: UInt8
    public let flags: UInt16
    public let current: UInt8
    public let worst: UInt8
    public let threshold: UInt8
    public let raw: [UInt8]
    public let rawValue: UInt64
    
    public init(id: UInt8, flags: UInt16, current: UInt8, worst: UInt8, threshold: UInt8, raw: [UInt8], rawValue: UInt64) {
        self.id = id
        self.flags = flags
        self.current = current
        self.worst = worst
        self.threshold = threshold
        self.raw = raw
        self.rawValue = rawValue
    }

    /// Bit 0 of the flags: the attribute predicts an imminent failure when it drops below its threshold.
    public var isPreFail: Bool { flags & 0x01 != 0 }
    /// Current normalized value at or below a non-zero threshold.
    public var isBelowThreshold: Bool { threshold > 0 && current <= threshold }
    /// The worst value recorded is at or below the threshold: it was crossed at some point.
    public var hasCrossedThreshold: Bool { threshold > 0 && worst <= threshold }
}

public struct ATASmartSnapshot: Codable, Equatable, Hashable {
    public let attributes: [ATASmartAttribute]
    public let model: String
    public let firmware: String
    public let serialNumber: String
    public let rotationRate: Int
    public let thresholdExceeded: Bool
    public let checksumValid: Bool
    // Also validate the checksum of the thresholds block.
    public let thresholdsChecksumValid: Bool
    
    public init(
        attributes: [ATASmartAttribute],
        model: String,
        firmware: String,
        serialNumber: String,
        rotationRate: Int,
        thresholdExceeded: Bool,
        checksumValid: Bool,
        thresholdsChecksumValid: Bool = true
    ) {
        self.attributes = attributes
        self.model = model
        self.firmware = firmware
        self.serialNumber = serialNumber
        self.rotationRate = rotationRate
        self.thresholdExceeded = thresholdExceeded
        self.checksumValid = checksumValid
        self.thresholdsChecksumValid = thresholdsChecksumValid
    }
}

public enum DiskHealthSnapshot: Codable, Equatable, Hashable {
    case nvme(NVMeSmartLog, NVMeIdentify)
    case ata(ATASmartSnapshot)

    public var serialNumber: String? {
        switch self {
        case .nvme(_, let id): return id.serialNumber
        case .ata(let snapshot): return snapshot.serialNumber
        }
    }

    // A dedicated nested key for ATA instead of a flat layout.
    // Backwards-compatible decode: tries the nested form first, falls back to the
    // legacy flat form (written by versions prior to this fix).
    enum CodingKeys: String, CodingKey {
        case protocolType = "protocol"
        case smart, identify
        case ataSnapshot   // new nested key
        // Legacy flat keys (decode-only, kept for backwards compatibility)
        case attributes, model, firmware, serialNumber, rotationRate, thresholdExceeded, checksumValid
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .protocolType) ?? "nvme"
        
        if type == "nvme" || container.contains(.smart) {
            let smart = try container.decode(NVMeSmartLog.self, forKey: .smart)
            let id = try container.decode(NVMeIdentify.self, forKey: .identify)
            self = .nvme(smart, id)
        } else if type == "ata" {
            // Try the new nested form first.
            if container.contains(.ataSnapshot) {
                let snapshot = try container.decode(ATASmartSnapshot.self, forKey: .ataSnapshot)
                self = .ata(snapshot)
            } else {
                // Backwards compatibility: read the legacy flat layout.
                let attrs = try container.decode([ATASmartAttribute].self, forKey: .attributes)
                let model = try container.decode(String.self, forKey: .model)
                let fw = try container.decode(String.self, forKey: .firmware)
                let sn = try container.decode(String.self, forKey: .serialNumber)
                let rot = try container.decode(Int.self, forKey: .rotationRate)
                let thresh = try container.decode(Bool.self, forKey: .thresholdExceeded)
                let check = try container.decode(Bool.self, forKey: .checksumValid)
                self = .ata(ATASmartSnapshot(
                    attributes: attrs,
                    model: model,
                    firmware: fw,
                    serialNumber: sn,
                    rotationRate: rot,
                    thresholdExceeded: thresh,
                    checksumValid: check,
                    thresholdsChecksumValid: true   // unknown in legacy format, assume valid
                ))
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown protocol: \(type)")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .nvme(let smart, let id):
            try container.encode("nvme", forKey: .protocolType)
            try container.encode(smart, forKey: .smart)
            try container.encode(id, forKey: .identify)
        case .ata(let snapshot):
            // Encode ATA as a proper nested object under "ataSnapshot".
            try container.encode("ata", forKey: .protocolType)
            try container.encode(snapshot, forKey: .ataSnapshot)
        }
    }
}
