import Foundation
import os
import AmanCore

/// Journal du mode diagnostic (correctifs §7) : événements des tests et lectures brutes,
/// exportés en JSON pour les testeurs. Aussi envoyé dans le journal système (Console.app, « AmanCheck »).
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    struct Entry: Codable {
        let date: Date
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var raw: [String: String] = [:]
    private let logger = Logger(subsystem: "com.aman.check", category: "diagnostic")
    private let maxEntries = 5000

    func log(_ category: String, _ message: String) {
        logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    /// Sortie brute d'une commande ou d'une lecture, pour l'export de diagnostic.
    /// Numéros de série (Mac, batterie, écrans) et UUID sont masqués avant d'être conservés.
    func record(_ key: String, _ value: String) {
        let redacted = Redaction.identifiers(in: value)
        lock.lock()
        defer { lock.unlock() }
        raw[key] = redacted
    }

    func snapshot() -> (entries: [Entry], raw: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        return (entries, raw)
    }
}
