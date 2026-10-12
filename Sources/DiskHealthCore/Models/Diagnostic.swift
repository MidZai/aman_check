import Foundation

public struct IOKitNodeDiagnostic: Codable, Equatable, Sendable {
    public let className: String
    public let properties: [String: String]
    
    public init(className: String, properties: [String: String]) {
        self.className = className
        self.properties = properties
    }
}

public struct Diagnostic: Codable, Equatable, Sendable {
    public let model: String
    public let bsdName: String
    public let protocolType: String
    public let mediumType: String
    public let reason: String
    public let usbVendorId: String?
    public let usbProductId: String?
    public let macosVersion: String
    public let architecture: String
    public let iokitParentChain: [IOKitNodeDiagnostic]
    
    public init(
        model: String,
        bsdName: String,
        protocolType: String,
        mediumType: String,
        reason: String,
        usbVendorId: String? = nil,
        usbProductId: String? = nil,
        macosVersion: String,
        architecture: String,
        iokitParentChain: [IOKitNodeDiagnostic] = []
    ) {
        self.model = model
        self.bsdName = bsdName
        self.protocolType = protocolType
        self.mediumType = mediumType
        self.reason = reason
        self.usbVendorId = usbVendorId
        self.usbProductId = usbProductId
        self.macosVersion = macosVersion
        self.architecture = architecture
        self.iokitParentChain = iokitParentChain
    }
    
    public init(physical: PhysicalDisk, chain: [IOKitNodeDiagnostic]? = nil) {
        self.model = physical.model
        self.bsdName = physical.bsdName
        self.protocolType = physical.protocolType.rawValue
        self.mediumType = physical.mediumType.rawValue
        
        switch physical.healthCapability {
        case .supported:
            self.reason = "supported"
        case .unsupported(let r):
            self.reason = r.rawValue
        }
        
        self.usbVendorId = physical.usbVendorID.map { String(format: "0x%04X", $0) }
        self.usbProductId = physical.usbProductID.map { String(format: "0x%04X", $0) }
        
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.macosVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        
        #if arch(arm64)
        self.architecture = "arm64"
        #elseif arch(x86_64)
        self.architecture = "x86_64"
        #else
        self.architecture = "unknown"
        #endif
        
        if let chain = chain {
            self.iokitParentChain = chain
        } else {
            self.iokitParentChain = IOKitDiagnostics.collectParentChain(bsdName: physical.bsdName)
        }
    }
}
