import Foundation
import IOKit

public enum IOKitDiagnostics {
    /// Keys whose value identifies the device or the user.
    static func isSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.contains("serial") || k.contains("uuid") || k.contains("guid") || k.contains("wwn")
            || k.contains("mac address") || k.contains("macaddress")
            || k.contains("volume name") || k.contains("volumename")
            || k.contains("username") || k.contains("user name")
            || k.contains("hostname") || k.contains("computer name")
    }

    /// Placeholder written in place of a masked value.
    public static var maskedPlaceholder: String { L("<hidden>", "<masqué>") }

    /// Readable, masked value. Recursive: IOKit stores the serial number in nested
    /// dictionaries (“Device Characteristics” › “Serial Number”), which used to be copied as is.
    public static func maskValue(key: String, value: Any) -> String {
        if isSensitive(key) {
            return maskedPlaceholder
        }
        if let dict = value as? [String: Any] {
            let inner = dict.keys.sorted().compactMap { k -> String? in
                guard let v = dict[k] else { return nil }
                return "\(k)=\(maskValue(key: k, value: v))"
            }
            return "{" + inner.joined(separator: ", ") + "}"
        }
        if let array = value as? [Any] {
            return "(" + array.map { maskValue(key: key, value: $0) }.joined(separator: ", ") + ")"
        }
        if let s = value as? String {
            // UUID format (8-4-4-4-12 hexadecimal).
            if s.count == 36 && s.filter({ $0 == "-" }).count == 4 {
                return maskedPlaceholder
            }
            if s.contains("/Users/") {
                return maskedPlaceholder
            }
            return s
        }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
        }
        if let n = value as? NSNumber {
            return n.stringValue
        }
        if let d = value as? Data {
            return "<data \(d.count) bytes>"
        }
        return "\(value)"
    }

    public static func sanitizeProperties(_ dict: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (k, v) in dict {
            result[k] = maskValue(key: k, value: v)
        }
        return result
    }
    
    public static func collectParentChain(bsdName: String) -> [IOKitNodeDiagnostic] {
        let targetService = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))
        guard targetService != 0 else { return [] }
        
        var chain: [IOKitNodeDiagnostic] = []
        var current = targetService
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &classNameBuf)
            let className = String(cString: classNameBuf)
            
            var propsDict: [String: String] = [:]
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = properties?.takeRetainedValue() as? [String: Any] {
                propsDict = sanitizeProperties(dict)
            }
            
            chain.append(IOKitNodeDiagnostic(className: className, properties: propsDict))
            
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }
        
        return chain
    }

    public static func collectProtocolCharacteristics(bsdName: String) -> [String: String]? {
        let service = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        if let dict = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "Protocol Characteristics" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        ) as? [String: Any] {
            return sanitizeProperties(dict)
        }
        return nil
    }

    public static func collectDeviceCharacteristics(bsdName: String) -> [String: String]? {
        let service = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        if let dict = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "Device Characteristics" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        ) as? [String: Any] {
            return sanitizeProperties(dict)
        }
        return nil
    }

    public static func collectUSBHostDevice(bsdName: String) -> USBHostDeviceDiagnostic? {
        let service = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var current = service
        IOObjectRetain(current)
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &classNameBuf)
            let className = String(cString: classNameBuf)
            
            if className == "IOUSBHostDevice" || className == "IOUSBDevice" || IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                var propsDict: [String: String] = [:]
                if IORegistryEntryCreateCFProperties(current, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = properties?.takeRetainedValue() as? [String: Any] {
                    propsDict = sanitizeProperties(dict)
                }
                
                var vidStr: String?
                if let vid = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                    vidStr = String(format: "0x%04X", vid.uint16Value)
                }
                var pidStr: String?
                if let pid = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "idProduct" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                    pidStr = String(format: "0x%04X", pid.uint16Value)
                }
                let vendorName = (IORegistryEntrySearchCFProperty(current, kIOServicePlane, "USB Vendor Name" as CFString, kCFAllocatorDefault, 0) as? String)
                    ?? (IORegistryEntrySearchCFProperty(current, kIOServicePlane, "kUSBVendorString" as CFString, kCFAllocatorDefault, 0) as? String)
                let productName = (IORegistryEntrySearchCFProperty(current, kIOServicePlane, "USB Product Name" as CFString, kCFAllocatorDefault, 0) as? String)
                    ?? (IORegistryEntrySearchCFProperty(current, kIOServicePlane, "kUSBProductString" as CFString, kCFAllocatorDefault, 0) as? String)
                var speedStr: String?
                if let speed = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "UsbLinkSpeed" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                    speedStr = formatUsbLinkSpeed(speed.uint64Value)
                } else if let speedProp = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "Device Speed" as CFString, kCFAllocatorDefault, 0) {
                    speedStr = "\(speedProp)"
                }
                var bcdStr: String?
                if let bcd = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "bcdUSB" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                    bcdStr = String(format: "0x%04X", bcd.uint16Value)
                }
                
                IOObjectRelease(current)
                return USBHostDeviceDiagnostic(
                    idVendor: vidStr,
                    idProduct: pidStr,
                    vendorName: vendorName,
                    productName: productName,
                    speed: speedStr,
                    bcdUSB: bcdStr,
                    properties: propsDict
                )
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
        return nil
    }

    public static func detectStorageDriver(bsdName: String) -> String? {
        let service = IOServiceGetMatchingService(ioMainPort, IOBSDNameMatching(ioMainPort, 0, bsdName))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var current = service
        IOObjectRetain(current)
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &classNameBuf)
            let className = String(cString: classNameBuf)
            
            if className.localizedCaseInsensitiveContains("UAS") {
                IOObjectRelease(current)
                return "UAS"
            }
            if let bProto = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "bInterfaceProtocol" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                if bProto.uint8Value == 0x62 {
                    IOObjectRelease(current)
                    return "UAS"
                } else if bProto.uint8Value == 0x50 {
                    IOObjectRelease(current)
                    return "BOT"
                }
            }
            if className.contains("MassStorage") {
                IOObjectRelease(current)
                return "BOT"
            }
            if className.contains("NVMe") {
                IOObjectRelease(current)
                return "NVMe"
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
        return nil
    }

    public static func formatUsbLinkSpeed(_ bps: UInt64) -> String {
        if bps >= 40_000_000_000 {
            return "USB4 (40 Gb/s)"
        } else if bps >= 20_000_000_000 {
            return "USB 3.2 Gen 2x2 (20 Gb/s)"
        } else if bps >= 10_000_000_000 {
            return "USB 3.2 Gen 2 (10 Gb/s)"
        } else if bps >= 5_000_000_000 {
            return "USB 3.0 (5 Gb/s)"
        } else if bps >= 480_000_000 {
            return "USB 2.0 (480 Mb/s)"
        } else if bps >= 12_000_000 {
            return "USB 1.1 (12 Mb/s)"
        } else {
            return "\(bps) bps"
        }
    }
}
