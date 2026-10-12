import Foundation
import IOKit

public protocol IORegistryNode: AnyObject {
    var bsdName: String? { get }
    var isWhole: Bool { get }
    var className: String { get }
    var parents: [IORegistryNode] { get }
    func conformsTo(className: String) -> Bool
}

public final class IOKitRegistryNode: IORegistryNode {
    public let entry: io_registry_entry_t
    private let shouldRelease: Bool
    
    public init(entry: io_registry_entry_t, shouldRelease: Bool = true) {
        self.entry = entry
        self.shouldRelease = shouldRelease
    }
    
    deinit {
        if shouldRelease && entry != 0 {
            IOObjectRelease(entry)
        }
    }
    
    public var bsdName: String? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault, 0) as? String
    }
    
    public var isWhole: Bool {
        (IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "Whole" as CFString, kCFAllocatorDefault, 0) as? Bool) == true
    }
    
    public var className: String {
        var name = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &name)
        return String(cString: name)
    }
    
    public func conformsTo(className: String) -> Bool {
        IOObjectConformsTo(entry, className) != 0
    }
    
    public var parents: [IORegistryNode] {
        var iter: io_iterator_t = 0
        let kr = IORegistryEntryGetParentIterator(entry, kIOServicePlane, &iter)
        guard kr == kIOReturnSuccess, iter != 0 else { return [] }
        defer { IOObjectRelease(iter) }
        
        var result: [IORegistryNode] = []
        var parent = IOIteratorNext(iter)
        while parent != 0 {
            result.append(IOKitRegistryNode(entry: parent, shouldRelease: true))
            parent = IOIteratorNext(iter)
        }
        return result
    }
}

public enum PhysicalDiskResolver {
    public static func resolvePhysicalDisks(from node: IORegistryNode) -> [String] {
        var physicalDisks: [String] = []
        var queue: [IORegistryNode] = [node]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            
            if current.isWhole && isPhysicalBlockDevice(current) {
                if let bsd = current.bsdName, !bsd.isEmpty, !physicalDisks.contains(bsd) {
                    physicalDisks.append(bsd)
                }
                // Stop traversing upwards from this physical disk
                continue
            }
            
            for parent in current.parents {
                queue.append(parent)
            }
        }
        
        return physicalDisks.sorted()
    }
    
    public static func isPhysicalBlockDevice(_ node: IORegistryNode) -> Bool {
        var current: IORegistryNode? = node
        var hasBlockStorage = false
        var isSyntheticStorage = false
        
        while let curr = current {
            if curr.conformsTo(className: "AppleAPFSContainerScheme") ||
               curr.conformsTo(className: "AppleRAIDSet") ||
               curr.conformsTo(className: "AppleSoftwareRAID") ||
               curr.conformsTo(className: "AppleRAID") ||
               curr.conformsTo(className: "CoreStorageLogical") ||
               curr.conformsTo(className: "CoreStorageLogicalVolumeGroup") {
                isSyntheticStorage = true
            }
            if curr.conformsTo(className: "IOBlockStorageDevice") {
                hasBlockStorage = true
            }
            current = curr.parents.first
        }
        
        return hasBlockStorage && !isSyntheticStorage
    }
}
