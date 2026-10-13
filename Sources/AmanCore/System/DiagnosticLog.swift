import Foundation
import os.log

/// Journal du mode diagnostic (correctifs §7) : événements des tests et lectures brutes,
/// exportés en JSON pour les testeurs. Aussi envoyé dans le journal système (Console.app, « AmanCheck »).
public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog()

    public struct Entry: Codable {
        public let date: Date
        public let category: String
        public let message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var raw: [String: String] = [:]
    // os_log plutôt que Logger (macOS 11) : même message dans Console.app, et disponible sur macOS 10.13 (Aman Legacy).
    private let osLog = OSLog(subsystem: "com.aman.check", category: "diagnostic")
    private let maxEntries = 5000

    public func log(_ category: String, _ message: String) {
        os_log("[%{public}@] %{public}@", log: osLog, type: .debug, category, message)
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    /// Sortie brute d'une commande ou d'une lecture, pour l'export de diagnostic.
    /// Numéros de série (Mac, batterie, écrans) et UUID sont masqués avant d'être conservés.
    public func record(_ key: String, _ value: String) {
        let redacted = Redaction.identifiers(in: value)
        lock.lock()
        defer { lock.unlock() }
        raw[key] = redacted
    }

    public func snapshot() -> (entries: [Entry], raw: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        return (entries, raw)
    }
}
