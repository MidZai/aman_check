import Foundation
import AppKit
import IOKit
import IOKit.graphics
import IOKit.hid
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

    /// Relevés répétés (température et ventilateurs en direct) : une connexion, et les clés de température
    /// trouvées une fois (sur Apple Silicon, parcourir toutes les clés à chaque relevé serait trop lent).
    final class Session {
        private let connection: UInt32
        private var temperatureKeys: [String]?
        private let fanCount: Int

        init?() {
            connection = aman_smc_open()
            guard connection != 0 else { return nil }
            fanCount = SensorCollector.value(connection, "FNum").map { Int($0) } ?? 0
        }

        deinit { aman_smc_close(connection) }

        /// Vitesse de chaque ventilateur, en tr/min (`nil` : illisible) ; vide sans ventilateur.
        func fanSpeeds() -> [Double?] {
            (0..<min(fanCount, 4)).map { SensorCollector.value(connection, "F\($0)Ac").flatMap { SMCValue.isPlausibleFanSpeed($0) ? $0 : nil } }
        }

        func cpuTemperature() -> Double? {
            if temperatureKeys == nil {
                if let key = SMCValue.intelCPUTemperatureKeys.first(where: { SensorCollector.value(connection, $0).map(SMCValue.isPlausibleTemperature) == true }) {
                    temperatureKeys = [key]
                } else {
                    temperatureKeys = SensorCollector.cpuCoreTemperatures(connection).map(\.0)
                }
            }
            return SensorAnalysis.averageTemperature((temperatureKeys ?? []).compactMap { SensorCollector.value(connection, $0) })
        }
    }

    fileprivate static func value(_ connection: UInt32, _ key: String) -> Double? {
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

    fileprivate static func cpuCoreTemperatures(_ connection: UInt32) -> [(String, Double)] {
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

/// Capteur intégré exposé par l'interface HID publique (norme HID « Sensors », page 0x20). Lecture seule :
/// aucun rapport n'est envoyé au capteur, sa configuration ne change pas. Seul le périphérique intégré est lu
/// (« Built-In »), jamais celui d'un écran ou d'un accessoire externe.
final class BuiltInHIDSensor {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let element: IOHIDElement

    /// `deviceUsage` : usage principal du périphérique ; `elementUsage` : champ à lire.
    init?(deviceUsage: Int, elementUsage: Int) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: deviceUsage] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: { (IOHIDDeviceGetProperty($0, "Built-In" as CFString) as? NSNumber)?.boolValue == true }),
              let element = (IOHIDDeviceCopyMatchingElements(device, [kIOHIDElementUsagePageKey: 0x20, kIOHIDElementUsageKey: elementUsage] as CFDictionary,
                                                             IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement])?.first
        else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        self.manager = manager
        self.device = device
        self.element = element
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Valeur actuelle, lue sur le capteur à chaque appel. `scaled` : appliquer l'exposant d'unité du champ.
    func read(scaled: Bool) -> Double? {
        // `IOHIDDeviceGetValueWithOptions` remplace le pointeur par une valeur qui appartient à l'élément (règle
        // « Get ») : elle ne doit jamais être libérée ici. La libérer faisait planter l'app au bout de quelques
        // centaines de lectures (objet libéré puis réutilisé par IOHIDLib). La valeur de départ, elle, est gérée
        // par Swift et reste vivante pendant l'appel.
        let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
        var value = Unmanaged.passUnretained(placeholder)
        // Option 1 (kIOHIDDeviceGetValueWithUpdate) : interroge le capteur au lieu de rendre la dernière valeur reçue.
        let status = IOHIDDeviceGetValueWithOptions(device, element, &value, 1)
        return withExtendedLifetime(placeholder) {
            guard status == kIOReturnSuccess else { return nil }
            let current = value.takeUnretainedValue()
            let number = scaled ? IOHIDValueGetScaledValue(current, IOHIDValueScaleType(kIOHIDValueScaleTypeExponent))
                                : Double(IOHIDValueGetIntegerValue(current))
            return number.isFinite ? number : nil
        }
    }
}

/// Capteur de luminosité intégré : usage Lumière ambiante 0x41, champ Éclairement 0x4D1, en lux.
/// Constaté sur le MacBookPro16,1 (T2) : périphérique USB interne « Ambient Light Sensor ».
/// TODO: à valider sur machine réelle : Apple Silicon (capteur derrière le SPU, peut-être invisible ici),
/// Mac Intel sans T2, iMac.
final class AmbientLightSensor {
    private let sensor: BuiltInHIDSensor

    init?() {
        guard let sensor = BuiltInHIDSensor(deviceUsage: 0x41, elementUsage: 0x4D1) else { return nil }
        self.sensor = sensor
    }

    /// Valeur actuelle, en lux.
    func lux() -> Double? {
        sensor.read(scaled: true).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// Une lecture, pour l'analyse automatique.
    static func readOnce() -> Double? {
        let value = AmbientLightSensor()?.lux()
        DiagnosticLog.shared.log("capteurs", "capteur de luminosité : \(value.map { String(format: "%.3f lux", $0) } ?? "illisible")")
        return value
    }
}
