import Foundation
import AppKit
import IOKit
import IOKit.graphics
import AmanCore
import CSMC

/// Capteurs (spec §6.6) : lecture du SMC, état du capot, luminosité de l'écran intégré, écrans externes.
/// Les décisions sont dans AmanCore (SensorAnalysis, SensorTests).
enum SensorCollector {
    /// Une lecture complète, hors du fil principal (quelques millisecondes).
    static func read() -> SensorReading {
        let connection = aman_smc_open()
        guard connection != 0 else {
            DiagnosticLog.shared.log("capteurs", "AppleSMC indisponible")
            return SensorReading(smcAvailable: false, method: "AppleSMC")
        }
        defer { aman_smc_close(connection) }
        var keys: [String] = []
        let fanCount = value(connection, "FNum").map { Int($0) }
        if fanCount != nil { keys.append("FNum") }
        var speeds: [Double?] = []
        for index in 0..<min(fanCount ?? 0, 4) {
            let key = "F\(index)Ac"
            let rpm = value(connection, key)
            if rpm != nil { keys.append(key) }
            speeds.append(rpm)
        }
        var temperature: Double?
        // Mac Intel : sondes connues, la première lisible et plausible.
        for key in SMCValue.intelCPUTemperatureKeys {
            if let t = value(connection, key), SMCValue.isPlausibleTemperature(t) {
                temperature = t
                keys.append(key)
                break
            }
        }
        // Apple Silicon : moyenne des sondes des cœurs, trouvées en parcourant les clés.
        if temperature == nil {
            let found = cpuCoreTemperatures(connection)
            temperature = SensorAnalysis.averageTemperature(found.map(\.1))
            if !found.isEmpty { keys.append("\(SMCValue.appleSiliconCPUTemperaturePrefix)* (\(found.count))") }
        }
        let reading = SensorReading(smcAvailable: true, fanCount: fanCount, fanSpeeds: speeds, cpuTemperature: temperature,
                                    method: "AppleSMC · " + (keys.isEmpty ? "—" : keys.joined(separator: ", ")))
        DiagnosticLog.shared.log("capteurs", "ventilateurs=\(fanCount.map(String.init) ?? "?") vitesses=\(speeds) temp=\(temperature.map { String(format: "%.1f", $0) } ?? "?") [\(reading.method ?? "")]")
        return reading
    }

    /// Vitesses actuelles des ventilateurs (pendant le test de performance).
    static func fanSpeeds() -> [Double?] {
        let connection = aman_smc_open()
        guard connection != 0 else { return [] }
        defer { aman_smc_close(connection) }
        let count = value(connection, "FNum").map { Int($0) } ?? 0
        return (0..<min(count, 4)).map { value(connection, "F\($0)Ac") }
    }

    private static func value(_ connection: UInt32, _ key: String) -> Double? {
        var type: (CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0)
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &type) { typePointer in
            typePointer.withMemoryRebound(to: CChar.self, capacity: 5) { typeChars in
                aman_smc_read(connection, key, typeChars, &bytes, &size)
            }
        }
        guard status == 0 else { return nil }
        let typeString = withUnsafeBytes(of: type) { raw in
            String(decoding: raw.prefix(4), as: UTF8.self)
        }
        return SMCValue.decode(type: typeString, bytes: Array(bytes.prefix(Int(size))))
    }

    private static func cpuCoreTemperatures(_ connection: UInt32) -> [(String, Double)] {
        guard let total = value(connection, "#KEY"), total > 0, total < 10_000 else { return [] }
        var result: [(String, Double)] = []
        var key: (CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0)
        for index in 0..<UInt32(total) {
            let status = withUnsafeMutablePointer(to: &key) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 5) { aman_smc_key_at(connection, index, $0) }
            }
            guard status == 0 else { break }
            let name = withUnsafeBytes(of: key) { String(decoding: $0.prefix(4), as: UTF8.self) }
            guard name.hasPrefix(SMCValue.appleSiliconCPUTemperaturePrefix), let t = value(connection, name),
                  SMCValue.isPlausibleTemperature(t) else { continue }
            result.append((name, t))
        }
        return result
    }

    // MARK: Capot, écran

    /// `AppleClamshellState` (IOPMrootDomain) : vrai capot fermé ; `nil` si la clé n'existe pas (Mac de bureau).
    static func clamshellClosed() -> Bool? {
        let root = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? Bool
    }

    /// Un écran autre que l'écran intégré est allumé.
    static func externalDisplayConnected() -> Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }

    /// Luminosité de l'écran intégré (0–1) par l'interface publique IODisplay. Lisible sur les Mac Intel ;
    /// sur Apple Silicon, cette interface ne répond généralement pas : `nil`, et la personne répond elle-même.
    static func builtInBrightness() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(mach_port_t(MACH_PORT_NULL), IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var level: Float = 0
            let status = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level)
            IOObjectRelease(service)
            if status == kIOReturnSuccess, (0...1).contains(level) { return Double(level) }
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}
