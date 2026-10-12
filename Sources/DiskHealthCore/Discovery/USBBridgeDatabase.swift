import Foundation

public struct USBBridge: Codable, Equatable, Hashable, Sendable {
    public let vendorId: String
    public let vendor: String
    public let notes: String?

    public init(vendorId: String, vendor: String, notes: String? = nil) {
        self.vendorId = vendorId
        self.vendor = vendor
        self.notes = notes
    }

    /// Numeric UInt16 vendor identifier (e.g. "0x152d" -> 0x152D).
    public var numericVendorID: UInt16? {
        let clean = vendorId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("0x") {
            return UInt16(clean.dropFirst(2), radix: 16)
        }
        return UInt16(clean, radix: 16) ?? UInt16(clean)
    }
}

public final class USBBridgeDatabase: Sendable {
    public static let shared = USBBridgeDatabase.loadDefault()

    /// Built-in fallback database so the app functions even if the resource is missing.
    public static let fallbackBridges: [USBBridge] = [
        USBBridge(vendorId: "0x152d", vendor: "JMicron", notes: "USB to SATA / NVMe bridges (e.g. JMS583, JMS567, JMS578)"),
        USBBridge(vendorId: "0x174c", vendor: "ASMedia", notes: "USB to SATA / NVMe bridges (e.g. ASM2362, ASM2364, ASM1153E)"),
        USBBridge(vendorId: "0x0bda", vendor: "Realtek", notes: "USB to NVMe / SATA bridges (e.g. RTL9210, RTL9210B)")
    ]

    public let bridges: [USBBridge]

    public init(bridges: [USBBridge]) {
        self.bridges = bridges
    }

    /// Loads bridges from raw JSON data.
    public static func load(from data: Data) throws -> [USBBridge] {
        try JSONDecoder().decode([USBBridge].self, from: data)
    }

    /// Loads bridges from a URL, throwing an error if reading or parsing fails.
    public static func load(from url: URL) throws -> [USBBridge] {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Loads the database looking in bundle resources or local path, falling back gracefully without crash.
    public static func loadDefault() -> USBBridgeDatabase {
        // `Bundle.module` calls fatalError when the SwiftPM resource bundle is neither next to the
        // executable nor in the build machine's .build folder, which crashed the app on any other Mac
        // as soon as a USB drive was analyzed. Look for the resource bundle without ever crashing.
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for directory in candidates.compactMap({ $0 }) {
            let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.lastPathComponent.hasSuffix("_DiskHealthCore.bundle") {
                if let url = Bundle(url: item)?.url(forResource: "usb-bridges", withExtension: "json"),
                   let loaded = try? load(from: url) {
                    return USBBridgeDatabase(bridges: loaded)
                }
            }
        }

        // 1. Try Bundle.main
        if let url = Bundle.main.url(forResource: "usb-bridges", withExtension: "json"),
           let loaded = try? load(from: url) {
            return USBBridgeDatabase(bridges: loaded)
        }

        // 2. Try file system paths relative to current working directory
        let searchPaths = [
            "Sources/DiskHealthCore/Resources/usb-bridges.json"
        ]
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path),
               let loaded = try? load(from: url) {
                return USBBridgeDatabase(bridges: loaded)
            }
        }

        // 3. Fallback
        return USBBridgeDatabase(bridges: fallbackBridges)
    }

    /// Finds a bridge definition by 16-bit USB Vendor ID.
    public func lookup(vendorID: UInt16) -> USBBridge? {
        bridges.first { $0.numericVendorID == vendorID }
    }

    /// Returns the vendor name if known.
    public func vendorName(for vendorID: UInt16) -> String? {
        lookup(vendorID: vendorID)?.vendor
    }

    /// Formats the bridge chip for display: e.g. "Realtek (0x0BDA)" or "Puce inconnue (0x1234)".
    public func formatChip(vendorID: UInt16) -> String {
        let hexStr = String(format: "0x%04X", vendorID)
        if let name = vendorName(for: vendorID) {
            return "\(name) (\(hexStr))"
        }
        return L("Unknown chip (\(hexStr))", "Puce inconnue (\(hexStr))")
    }
}
