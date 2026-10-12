import Foundation

public struct Volume: Codable, Identifiable, Hashable {
    public var id: String { bsdName }
    public let bsdName: String
    public let name: String
    public let mountPoint: String
    public let format: String
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let physicalDiskBSDNames: [String]
    
    public var physicalDiskBSDName: String? {
        physicalDiskBSDNames.first
    }
    
    public init(bsdName: String, name: String, mountPoint: String, format: String, totalBytes: UInt64, availableBytes: UInt64, physicalDiskBSDNames: [String]) {
        self.bsdName = bsdName
        self.name = name
        self.mountPoint = mountPoint
        self.format = format
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.physicalDiskBSDNames = physicalDiskBSDNames
    }
    
    public init(bsdName: String, name: String, mountPoint: String, format: String, totalBytes: UInt64, availableBytes: UInt64, physicalDiskBSDName: String?) {
        self.init(
            bsdName: bsdName,
            name: name,
            mountPoint: mountPoint,
            format: format,
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            physicalDiskBSDNames: physicalDiskBSDName.map { [$0] } ?? []
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case bsdName, name, mountPoint, format, totalBytes, availableBytes, physicalDiskBSDNames, physicalDiskBSDName
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bsdName = try container.decode(String.self, forKey: .bsdName)
        self.name = try container.decode(String.self, forKey: .name)
        self.mountPoint = try container.decode(String.self, forKey: .mountPoint)
        self.format = try container.decode(String.self, forKey: .format)
        self.totalBytes = try container.decode(UInt64.self, forKey: .totalBytes)
        self.availableBytes = try container.decode(UInt64.self, forKey: .availableBytes)
        
        if let names = try container.decodeIfPresent([String].self, forKey: .physicalDiskBSDNames) {
            self.physicalDiskBSDNames = names
        } else if let singleName = try container.decodeIfPresent(String.self, forKey: .physicalDiskBSDName) {
            self.physicalDiskBSDNames = [singleName]
        } else {
            self.physicalDiskBSDNames = []
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bsdName, forKey: .bsdName)
        try container.encode(name, forKey: .name)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(format, forKey: .format)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(availableBytes, forKey: .availableBytes)
        try container.encode(physicalDiskBSDNames, forKey: .physicalDiskBSDNames)
        try container.encodeIfPresent(physicalDiskBSDName, forKey: .physicalDiskBSDName)
    }
}
