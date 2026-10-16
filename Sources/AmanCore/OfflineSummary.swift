import Foundation
import DiskHealthCore

/// Résumé compact du rapport, encodé dans le QR code hors ligne du PDF (spec §8.4).
///
/// Texte brut, une clé=valeur par ligne, lisible par n'importe quel lecteur de QR code sans app dédiée.
/// Aucune URL, aucun serveur. Clés et valeurs en anglais (le même code se lit partout), sauf le nom
/// commercial du modèle, qui suit la langue du rapport. Le QR code **ne prouve rien** : la légende du PDF le dit (lexique, spec §3).
public enum OfflineSummary {
    public static let schemaVersion = 1
    public static let maximumLength = 500

    public static func text(for report: ConditionReport) -> String {
        let summary = ReportSummary(report: report)
        func m(_ id: String) -> Measurement? { report.measurement(id) }

        var lines = ["AMAN CHECK SUMMARY v\(schemaVersion)"]
        lines.append("date=" + ISO8601DateFormatter.string(from: report.generatedAt, timeZone: .current, formatOptions: [.withInternetDateTime]))
        lines.append("report=\(report.reportID)")
        lines.append("model=\(report.profile.modelIdentifier)")
        if let name = report.profile.model?.displayName { lines.append("name=\(name)") }
        // Les 4 derniers caractères seulement, jamais plus, même si la valeur stockée était plus longue.
        if let serial = m(MetricID.serial)?.value.flatMap(text) {
            lines.append("serial_last4=\(String(serial.suffix(4)))")
        }
        if report.profile.hasBattery {
            lines.append("battery_cycles=\(int(m(MetricID.batteryCycles)).map(String.init) ?? "n/a")")
            lines.append("battery_capacity=\(int(m(MetricID.batteryHealth)).map { "\($0)%" } ?? "n/a")")
        }
        lines.append("ssd_hours=\(int(m(MetricID.storagePowerOnHours)).map(String.init) ?? "n/a")")
        lines.append("activation_lock=\(lockState(m(MetricID.activationLock), good: "off", problem: "ON"))")
        lines.append("mdm=\(lockState(m(MetricID.mdm), good: "no signal", problem: "ENROLLED", info: "no signal"))")
        lines.append("apple_account=\(accountState(m(MetricID.appleAccount)))")
        var counts = "good \(summary.good), watch \(summary.watch), problem \(summary.problem), not tested \(summary.notTested)"
        if summary.toCheck > 0 { counts += ", check manually \(summary.toCheck)" }
        lines.append("counts=\(counts)")
        lines.append("tests=\(summary.testsDone)/\(summary.testsPlanned)")
        if report.simulated { lines.append("simulated=yes") }

        var result = lines.joined(separator: "\n")
        // Garde-fou de taille : le nom commercial est la seule ligne facultative.
        if result.count > maximumLength {
            result = lines.filter { !$0.hasPrefix("name=") }.joined(separator: "\n")
        }
        if result.count > maximumLength {
            result = String(result.prefix(maximumLength))
        }
        return result
    }

    private static func text(_ value: MeasuredValue) -> String? {
        if case .text(let s) = value { return s }
        return nil
    }

    private static func int(_ m: Measurement?) -> Int64? {
        guard let m, m.status != .unavailable else { return nil }
        return m.value?.intValue
    }

    /// Verdict prudent : seul un état réellement jugé est écrit ; le reste est « not verified ».
    private static func lockState(_ m: Measurement?, good: String, problem: String, info: String? = nil) -> String {
        switch m?.status {
        case .good?: return good
        case .problem?: return problem
        case .info?: return info ?? "not verified"
        default: return "not verified"
        }
    }

    private static func accountState(_ m: Measurement?) -> String {
        guard let m else { return "not verified" }
        switch m.status {
        case .good: return "none"
        case .watch: return "SIGNED IN" + (m.value?.intValue.map { $0 > 1 ? " (\($0))" : "" } ?? "")
        default: return "not verified"
        }
    }
}
