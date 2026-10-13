import Foundation
import IOKit
import DiskArbitration

public enum ProtocolDetector {
    public static let ataSmartPluginUUIDs: Set<String> = [
        "24514B7A-2804-11D6-8A02-003065704866",
        "5E659F92-20D3-11D6-BDB5-0003935A76B2",
        "08ABE21C-20D4-11D6-8DF6-0003935A76B2"
    ]

    /// Inspects an `IOCFPlugInTypes` dictionary from IOKit to determine whether an ATA S.M.A.R.T. plugin is declared.
    public static func isATASmartPluginPresent(in plugins: [String: Any]) -> Bool {
        plugins.keys.contains { key in
            ataSmartPluginUUIDs.contains { $0.caseInsensitiveCompare(key) == .orderedSame }
        }
    }

    public static func detect(bsdName: String) -> (StorageProtocol, MediumType, HealthCapability) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return (.unknown, .unknown, .unsupported(reason: .noSmartInterface))
        }

        // Direct lookup by BSD name (instead of walking every IOMedia in the system).
        let targetService = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))

        guard targetService != 0 else {
            return (.unknown, .unknown, .unsupported(reason: .noSmartInterface))
        }

        var isNVMeSmartCapable = false
        var isATASmartCapable = false
        var hasATASMARTPlugin = false
        var isPCIeAHCI = false
        var mediumTypeStr: String? = nil

        var current = targetService
        IOObjectRetain(current)

        while current != 0 {
            if let capable = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0) as? Bool, capable {
                isNVMeSmartCapable = true
            }

            if let capable = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "SMART Capable" as CFString, kCFAllocatorDefault, 0) as? Bool, capable {
                isATASmartCapable = true
            }

            if !hasATASMARTPlugin,
               let plugins = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "IOCFPlugInTypes" as CFString, kCFAllocatorDefault, 0) as? [String: Any] {
                if isATASmartPluginPresent(in: plugins) {
                    hasATASMARTPlugin = true
                }
            }

            if let devChars = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "Device Characteristics" as CFString, kCFAllocatorDefault, 0) as? [String: Any] {
                if mediumTypeStr == nil, let mt = devChars["Medium Type"] as? String {
                    mediumTypeStr = mt
                }
            }

            if let protChars = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0) as? [String: Any] {
                if let interconnect = protChars["Physical Interconnect"] as? String, interconnect.contains("PCI") {
                    isPCIeAHCI = true
                }
            }

            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }

        if !hasATASMARTPlugin {
            if let plugins = IORegistryEntrySearchCFProperty(
                targetService,
                kIOServicePlane,
                "IOCFPlugInTypes" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            ) as? [String: Any] {
                if isATASmartPluginPresent(in: plugins) {
                    hasATASMARTPlugin = true
                }
            }
        }

        var daProtocol = ""
        var daModel = ""
        if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, targetService),
           let desc = DADiskCopyDescription(disk) as? [String: Any] {
            daProtocol = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
            daModel = desc[kDADiskDescriptionDeviceModelKey as String] as? String ?? ""
        }

        IOObjectRelease(targetService)

        let mediumType: MediumType
        if mediumTypeStr == "Solid State" {
            mediumType = .solidState
        } else if mediumTypeStr == "Rotational" {
            mediumType = .rotational
        } else {
            mediumType = .unknown
        }

        if isNVMeSmartCapable {
            return (.nvme, mediumType, .supported)
        }
        if isATASmartCapable && (hasATASMARTPlugin || !daProtocol.contains("USB")) {
            if isPCIeAHCI {
                return (.pcieAhci, mediumType, .supported)
            }
            return (.ata, mediumType, .supported)
        }
        if daProtocol == "USB" || daProtocol == "USB-C" || daProtocol == "USB (Attached SCSI)" {
            return (.usb, mediumType, .unsupported(reason: .usbBridge))
        }
        if daProtocol == "Secure Digital" || daProtocol == "SD" || daModel.contains("SD Card Reader") {
            return (.sdCard, mediumType, .unsupported(reason: .sdCardReader))
        }
        if daProtocol == "Virtual Interface" || daProtocol == "Disk Image" || daModel.contains("VMware") || daModel.contains("VBOX") || daModel.contains("Parallels") || daModel.contains("Virtual") {
            return (.virtualDisk, mediumType, .unsupported(reason: .virtualDisk))
        }

        return (.unknown, mediumType, .unsupported(reason: .noSmartInterface))
    }
}
