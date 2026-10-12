import Foundation

public enum DriveClassifier {
    /// Determines whether the drive represents a physical disk or an excluded virtual/network device.
    /// Excludes:
    /// - Physical Interconnect Location == "File" (Disk Images)
    /// - Physical Interconnect == "Virtual Interface" (VM / Virtual disks)
    /// - RAM Disks ("RAM Disk", bsdName prefix "ram")
    /// - Network disks ("Network Disk", "NFS", "SMB", "AFP")
    /// - Disk images ("Disk Image")
    public static func isPhysicalDrive(
        protocolCharacteristics: [String: Any]?,
        deviceProtocol: String? = nil,
        bsdName: String? = nil
    ) -> Bool {
        if let bsd = bsdName?.lowercased(), bsd.hasPrefix("ram") {
            return false
        }
        if let location = protocolCharacteristics?["Physical Interconnect Location"] as? String {
            if location.caseInsensitiveCompare("File") == .orderedSame {
                return false
            }
        }
        if let interconnect = protocolCharacteristics?["Physical Interconnect"] as? String {
            let lower = interconnect.lowercased()
            if lower.contains("virtual") || lower.contains("ram disk") || lower.contains("file") {
                return false
            }
        }
        if let proto = deviceProtocol {
            let lower = proto.lowercased()
            if lower.contains("virtual") || lower.contains("disk image") || lower.contains("network")
                || lower == "nfs" || lower == "smb" || lower == "afp" {
                return false
            }
        }
        return true
    }

    /// Classifies the drive connection into internal or external drive types.
    public static func classify(
        protocolCharacteristics: [String: Any]?,
        deviceProtocol: String? = nil,
        isInternalHint: Bool? = nil,
        protocolType: StorageProtocol? = nil
    ) -> DriveConnection {
        let locationStr = (protocolCharacteristics?["Physical Interconnect Location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInternal: Bool
        if let loc = locationStr, !loc.isEmpty {
            isInternal = loc.caseInsensitiveCompare("Internal") == .orderedSame
        } else {
            isInternal = isInternalHint ?? true
        }

        let rawInterconnect = ((protocolCharacteristics?["Physical Interconnect"] as? String) ?? (deviceProtocol ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = rawInterconnect.uppercased()

        if isInternal {
            if protocolType == .pcieAhci || upper.contains("AHCI") {
                return .internalAHCI
            }
            if upper.contains("NVME") || upper == "PCI-EXPRESS" || upper == "PCI" || upper.contains("APPLE FABRIC") || protocolType == .nvme {
                return .internalNVMe
            }
            if upper.contains("SATA") || protocolType == .ata {
                return .internalSATA
            }
            if rawInterconnect.isEmpty {
                if protocolType == .pcieAhci { return .internalAHCI }
                if protocolType == .ata { return .internalSATA }
                return .internalNVMe
            }
            return .other(rawInterconnect)
        } else {
            if upper.contains("THUNDERBOLT") || upper == "PCI-EXPRESS" || upper.contains("NVME") || upper.contains("PCI") || protocolType == .nvme {
                return .thunderboltNVMe
            }
            if upper.contains("USB") || protocolType == .usb {
                return .usb
            }
            if rawInterconnect.isEmpty {
                return .other("External")
            }
            return .other(rawInterconnect)
        }
    }
}
