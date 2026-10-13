import Foundation
import IOKit

/// Résultat d'une commande : sortie, erreurs et code de retour. `nil` en cas d'échec de lancement ou de délai dépassé.
public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Commandes système sans API (spec §5) : délai maximal, stderr capturé, jamais sur le fil principal.
public enum Shell {
    @available(macOS 10.15, *)
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) async -> CommandResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(path, arguments, timeout: timeout))
            }
        }
    }

    /// Plusieurs commandes en parallèle (chacune garde son délai) ; résultats dans l'ordre des commandes.
    /// Synchrone : à appeler hors du fil principal.
    public static func runAllSync(_ commands: [() -> CommandResult?]) -> [CommandResult?] {
        var results = [CommandResult?](repeating: nil, count: commands.count)
        let lock = NSLock()
        let group = DispatchGroup()
        // Une tâche par commande (pas concurrentPerform, limité au nombre de cœurs : sur un vieux Mac
        // à deux cœurs, les commandes attendraient leur tour).
        for (index, command) in commands.enumerated() {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                let result = command()
                lock.lock()
                results[index] = result
                lock.unlock()
            }
        }
        group.wait()
        return results
    }

    /// Version synchrone (Aman Legacy, macOS 10.13) : à appeler hors du fil principal.
    public static func runSync(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandResult? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // Sorties en anglais quelle que soit la langue du Mac : les analyseurs ne dépendent pas de la traduction.
        process.environment = ["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Lecture en continu : un tampon plein bloquerait la commande.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            DiagnosticLog.shared.log("shell", "échec du lancement de \(path) : \(error)")
            // Ferme les tubes pour libérer les deux lecteurs en attente de fin de fichier.
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            return nil
        }
        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            DiagnosticLog.shared.log("shell", "délai dépassé : \(path) \(arguments.joined(separator: " "))")
            return nil
        }
        group.wait()
        return CommandResult(stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
                             exitCode: process.terminationStatus)
    }
}

/// Lectures directes (sysctl, IOKit) : préférées aux sorties texte (spec §5).
/// IOKit : `MACH_PORT_NULL` est l'équivalent documenté de `kIOMainPortDefault` (macOS 12 seulement).
public enum SystemReader {
    public static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Entier 32 ou 64 bits : le tampon est mis à zéro, sysctl n'écrit que la taille réelle (petit-boutiste).
    public static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    public static var modelIdentifier: String { sysctlString("hw.model") ?? "Mac" }

    public static var isAppleSilicon: Bool { sysctlInt("hw.optional.arm64") == 1 }

    /// Numéro de série complet (IOPlatformSerialNumber). Jamais affiché en entier.
    public static var serialNumber: String? {
        let service = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }

    /// Propriétés de `AppleSmartBattery` ; `nil` si aucune batterie (Mac de bureau).
    public static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }
}
