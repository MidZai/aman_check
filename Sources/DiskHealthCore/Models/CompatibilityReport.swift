import Foundation

public struct USBHostDeviceDiagnostic: Codable, Equatable, Sendable {
    public let idVendor: String?
    public let idProduct: String?
    public let vendorName: String?
    public let productName: String?
    public let speed: String?
    public let bcdUSB: String?
    public let properties: [String: String]?

    public init(
        idVendor: String? = nil,
        idProduct: String? = nil,
        vendorName: String? = nil,
        productName: String? = nil,
        speed: String? = nil,
        bcdUSB: String? = nil,
        properties: [String: String]? = nil
    ) {
        self.idVendor = idVendor
        self.idProduct = idProduct
        self.vendorName = vendorName
        self.productName = productName
        self.speed = speed
        self.bcdUSB = bcdUSB
        self.properties = properties
    }
}

public struct RawSmartAttributeDiagnostic: Codable, Equatable, Sendable {
    public let id: UInt8?
    public let key: String
    public let name: String
    public let rawValue: UInt64
    public let current: UInt8?
    public let worst: UInt8?
    public let threshold: UInt8?
    public let flags: UInt16?

    public init(
        id: UInt8? = nil,
        key: String,
        name: String,
        rawValue: UInt64,
        current: UInt8? = nil,
        worst: UInt8? = nil,
        threshold: UInt8? = nil,
        flags: UInt16? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.rawValue = rawValue
        self.current = current
        self.worst = worst
        self.threshold = threshold
        self.flags = flags
    }
}

public struct CompatibilityReport: Codable, Equatable, Sendable {
    public let amanVersion: String
    public let macosVersion: String
    public let architecture: String
    public let model: String
    public let bsdName: String
    public let connection: String
    public let storageDriver: String?
    public let smartAvailability: String
    public let errorCode: String?
    public let satTranslationActive: Bool
    public let protocolCharacteristics: [String: String]?
    public let deviceCharacteristics: [String: String]?
    public let usbHostDevice: USBHostDeviceDiagnostic?
    public let rawSmartAttributes: [RawSmartAttributeDiagnostic]?
    public let iokitParentChain: [IOKitNodeDiagnostic]

    public init(
        amanVersion: String = "1.0.0",
        macosVersion: String,
        architecture: String,
        model: String,
        bsdName: String,
        connection: String,
        storageDriver: String? = nil,
        smartAvailability: String,
        errorCode: String? = nil,
        satTranslationActive: Bool = false,
        protocolCharacteristics: [String: String]? = nil,
        deviceCharacteristics: [String: String]? = nil,
        usbHostDevice: USBHostDeviceDiagnostic? = nil,
        rawSmartAttributes: [RawSmartAttributeDiagnostic]? = nil,
        iokitParentChain: [IOKitNodeDiagnostic] = []
    ) {
        self.amanVersion = amanVersion
        self.macosVersion = macosVersion
        self.architecture = architecture
        self.model = model
        self.bsdName = bsdName
        self.connection = connection
        self.storageDriver = storageDriver
        self.smartAvailability = smartAvailability
        self.errorCode = errorCode
        self.satTranslationActive = satTranslationActive
        self.protocolCharacteristics = protocolCharacteristics
        self.deviceCharacteristics = deviceCharacteristics
        self.usbHostDevice = usbHostDevice
        self.rawSmartAttributes = rawSmartAttributes
        self.iokitParentChain = iokitParentChain
    }

    public static func collect(
        physical: PhysicalDisk,
        snapshot: DiskHealthSnapshot? = nil,
        amanVersion: String = "1.0.0"
    ) -> CompatibilityReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macosVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        #if arch(arm64)
        let architecture = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        let architecture = "Intel (x86_64)"
        #else
        let architecture = "unknown"
        #endif

        let protoChars = IOKitDiagnostics.collectProtocolCharacteristics(bsdName: physical.bsdName) ?? [
            "Physical Interconnect": physical.protocolType.rawValue.uppercased(),
            "Physical Interconnect Location": physical.isInternal ? "Internal" : "External"
        ]
        let devChars = IOKitDiagnostics.collectDeviceCharacteristics(bsdName: physical.bsdName) ?? [
            "Product Name": physical.model,
            "Serial Number": "<masqué>"
        ]
        let parentChain = IOKitDiagnostics.collectParentChain(bsdName: physical.bsdName)

        let usbDevice = IOKitDiagnostics.collectUSBHostDevice(bsdName: physical.bsdName) ?? (
            (physical.usbVendorID != nil || physical.driveConnection == .usb) ? USBHostDeviceDiagnostic(
                idVendor: physical.usbVendorID.map { String(format: "0x%04X", $0) },
                idProduct: physical.usbProductID.map { String(format: "0x%04X", $0) },
                vendorName: physical.usbVendorName,
                productName: physical.usbProductName,
                speed: physical.usbLinkSpeedLabel,
                bcdUSB: physical.usbBcdUSB.map { String(format: "0x%04X", $0) },
                properties: nil
            ) : nil
        )

        let storageDriver = IOKitDiagnostics.detectStorageDriver(bsdName: physical.bsdName) ?? physical.usbProtocolLabel

        let smartAvail: String
        var errCode: String? = nil
        switch physical.smartAvailability {
        case .available:
            smartAvail = "available"
        case .disabledOnDrive:
            smartAvail = "disabledOnDrive"
        case .notSupportedByEnclosure:
            smartAvail = "notSupportedByEnclosure"
        case .driverRequired:
            smartAvail = "driverRequired"
        case .error(let code):
            smartAvail = "error"
            errCode = "\(code)"
        case .none:
            switch physical.healthCapability {
            case .supported:
                smartAvail = "available"
            case .unsupported(let reason):
                smartAvail = reason.rawValue
                if case .readFailed(let code) = reason {
                    errCode = code
                }
            }
        }

        if errCode == nil, case .unsupported(reason: .readFailed(let code)) = physical.healthCapability {
            errCode = code
        }

        var rawAttributes: [RawSmartAttributeDiagnostic]? = nil
        if let snapshot = snapshot {
            switch snapshot {
            case .ata(let ata):
                rawAttributes = ata.attributes.map { attr in
                    let attrName = ATACatalog.genericAttributes[attr.id]?.name ?? "Attribute \(String(format: "0x%02X", attr.id))"
                    return RawSmartAttributeDiagnostic(
                        id: attr.id,
                        key: String(format: "0x%02X", attr.id),
                        name: attrName,
                        rawValue: attr.rawValue,
                        current: attr.current,
                        worst: attr.worst,
                        threshold: attr.threshold,
                        flags: attr.flags
                    )
                }
            case .nvme(let smart, _):
                rawAttributes = [
                    RawSmartAttributeDiagnostic(key: "critical_warning", name: "Critical Warning", rawValue: UInt64(smart.criticalWarning)),
                    RawSmartAttributeDiagnostic(key: "composite_temperature_kelvin", name: "Composite Temperature (K)", rawValue: UInt64(smart.compositeTemperatureKelvin)),
                    RawSmartAttributeDiagnostic(key: "available_spare", name: "Available Spare (%)", rawValue: UInt64(smart.availableSpare)),
                    RawSmartAttributeDiagnostic(key: "available_spare_threshold", name: "Available Spare Threshold (%)", rawValue: UInt64(smart.availableSpareThreshold)),
                    RawSmartAttributeDiagnostic(key: "percentage_used", name: "Percentage Used", rawValue: UInt64(smart.percentageUsed)),
                    RawSmartAttributeDiagnostic(key: "data_units_read", name: "Data Units Read", rawValue: smart.dataUnitsRead),
                    RawSmartAttributeDiagnostic(key: "data_units_written", name: "Data Units Written", rawValue: smart.dataUnitsWritten),
                    RawSmartAttributeDiagnostic(key: "host_read_commands", name: "Host Read Commands", rawValue: smart.hostReadCommands),
                    RawSmartAttributeDiagnostic(key: "host_write_commands", name: "Host Write Commands", rawValue: smart.hostWriteCommands),
                    RawSmartAttributeDiagnostic(key: "controller_busy_time_minutes", name: "Controller Busy Time (min)", rawValue: smart.controllerBusyTimeMinutes),
                    RawSmartAttributeDiagnostic(key: "power_cycles", name: "Power Cycles", rawValue: smart.powerCycles),
                    RawSmartAttributeDiagnostic(key: "power_on_hours", name: "Power On Hours", rawValue: smart.powerOnHours),
                    RawSmartAttributeDiagnostic(key: "unsafe_shutdowns", name: "Unsafe Shutdowns", rawValue: smart.unsafeShutdowns),
                    RawSmartAttributeDiagnostic(key: "media_errors", name: "Media Errors", rawValue: smart.mediaErrors),
                    RawSmartAttributeDiagnostic(key: "error_log_entries", name: "Error Log Entries", rawValue: smart.errorLogEntries)
                ]
            }
        }

        return CompatibilityReport(
            amanVersion: amanVersion,
            macosVersion: macosVersion,
            architecture: architecture,
            model: physical.model,
            bsdName: physical.bsdName,
            connection: physical.driveConnection.badgeLabel,
            storageDriver: storageDriver,
            smartAvailability: smartAvail,
            errorCode: errCode,
            satTranslationActive: physical.isSATTranslationActive,
            protocolCharacteristics: protoChars,
            deviceCharacteristics: devChars,
            usbHostDevice: usbDevice,
            rawSmartAttributes: rawAttributes,
            iokitParentChain: parentChain
        )
    }

    public static func generateJSON(report: CompatibilityReport, knownSerials: [String] = []) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let rawData = try encoder.encode(report)
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: rawData, options: []) else {
            return rawData
        }
        
        var toMask: [String] = []
        for s in knownSerials where !s.isEmpty && s.count >= 5 {
            toMask.append(s)
        }
        
        let homeDir = NSHomeDirectory()
        if !homeDir.isEmpty && homeDir != "/" {
            toMask.append(homeDir)
        }
        let userName = NSUserName()
        if !userName.isEmpty && userName != "root" && userName.count >= 3 {
            toMask.append("/Users/\(userName)")
        }
        if let hostName = Host.current().localizedName, !hostName.isEmpty, hostName.count >= 3 {
            toMask.append(hostName)
        }
        
        func redact(value: Any) -> Any {
            if let str = value as? String {
                var maskedStr = str
                for mask in toMask {
                    maskedStr = maskedStr.replacingOccurrences(of: mask, with: "<masqué>")
                }
                return maskedStr
            } else if let dict = value as? [String: Any] {
                var newDict: [String: Any] = [:]
                for (k, v) in dict {
                    newDict[k] = redact(value: v)
                }
                return newDict
            } else if let array = value as? [Any] {
                return array.map { redact(value: $0) }
            }
            return value
        }
        
        let redactedObject = redact(value: jsonObject)
        return (try? JSONSerialization.data(withJSONObject: redactedObject, options: [.prettyPrinted, .sortedKeys])) ?? rawData
    }
}
