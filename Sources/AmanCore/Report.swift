import Foundation
import DiskHealthCore

/// Rapport d'état : rendu pur de la liste de mesures, des tests et des métadonnées (spec §4, §8).
public struct ConditionReport: Codable, Sendable {
    public static let schemaVersion = 1
    /// Version de la procédure de contrôle (ce qui est mesuré et comment). À incrémenter quand elle change.
    public static let procedureVersion = "1.0"

    public let schemaVersion: Int
    public let procedureVersion: String
    public let reportID: String
    public let generatedAt: Date
    public let appVersion: String
    /// Niveau 1 : rapport d'état local, sans certification (spec §2).
    public let trustLevel: Int
    public let profile: DeviceProfile
    public let measurements: [Measurement]
    public let tests: [TestResult]
    /// Tests prévus pour cette machine (pour « 6 tests sur 8 réalisés »).
    public let plannedTests: [TestID]
    public var sellerName: String?
    /// Profil simulé avec `--simulate-model` (développement) : le rapport ne décrit pas fidèlement ce Mac.
    /// Affiché dans le PDF ; un tel rapport ne peut pas être publié (niveau 2).
    public let simulated: Bool

    public init(reportID: String = ConditionReport.makeID(), generatedAt: Date = Date(), appVersion: String,
                profile: DeviceProfile, measurements: [Measurement], tests: [TestResult], plannedTests: [TestID],
                sellerName: String? = nil) {
        self.schemaVersion = Self.schemaVersion
        self.procedureVersion = Self.procedureVersion
        self.reportID = reportID
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.trustLevel = 1
        self.profile = profile
        self.measurements = measurements
        self.tests = tests
        self.plannedTests = plannedTests
        self.sellerName = sellerName
        self.simulated = profile.isSimulated
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, procedureVersion, reportID, generatedAt, appVersion, trustLevel, profile,
             measurements, tests, plannedTests, sellerName, simulated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        procedureVersion = try c.decode(String.self, forKey: .procedureVersion)
        reportID = try c.decode(String.self, forKey: .reportID)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        trustLevel = try c.decode(Int.self, forKey: .trustLevel)
        profile = try c.decode(DeviceProfile.self, forKey: .profile)
        measurements = try c.decode([Measurement].self, forKey: .measurements)
        tests = try c.decode([TestResult].self, forKey: .tests)
        plannedTests = try c.decode([TestID].self, forKey: .plannedTests)
        sellerName = try c.decodeIfPresent(String.self, forKey: .sellerName)
        // Rapports antérieurs au champ : le profil fait foi.
        simulated = try c.decodeIfPresent(Bool.self, forKey: .simulated) ?? profile.isSimulated
    }

    public func measurement(_ id: String) -> Measurement? {
        measurements.first { $0.id == id }
    }

    public func result(_ test: TestID) -> TestResult? {
        tests.first { $0.test == test }
    }

    /// Identifiant lisible, non devinable : « AC-7K3P-Q2XD » (alphabet sans 0/O/1/I).
    public static func makeID() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var rng = SystemRandomNumberGenerator()
        let chars = (0..<8).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] }
        return "AC-\(String(chars[0..<4]))-\(String(chars[4..<8]))"
    }
}

/// Synthèse sans note globale : « X bons · Y à surveiller · Z problèmes · N non testés ».
public struct ReportSummary: Sendable, Equatable {
    public var good = 0
    public var watch = 0
    public var problem = 0
    public var notTested = 0
    public var toCheck = 0
    public var testsDone = 0
    public var testsPlanned = 0
    /// Activation Lock, MDM ou machine virtuelle : remontés en tête, en rouge.
    public var blockers: [Measurement] = []

    public init(report: ConditionReport) {
        // Seules les mesures « Essentiel » jugées comptent : le détail avancé ne gonfle pas les compteurs.
        for m in report.measurements where MetricCatalog.contains(m.id) {
            let info = MetricCatalog.info(for: m.id)
            guard info.isJudged, info.level == .essential || m.status == .problem || m.status == .watch else { continue }
            count(m.status)
        }
        for test in report.plannedTests {
            if let result = report.result(test) {
                count(result.status)
                if result.outcome == .passed || result.outcome == .failed { testsDone += 1 }
            } else {
                notTested += 1
            }
        }
        testsPlanned = report.plannedTests.count
        blockers = report.measurements.filter {
            ($0.id == MetricID.activationLock || $0.id == MetricID.mdm || $0.id == MetricID.virtualMachine) && $0.status == .problem
        }
    }

    private mutating func count(_ status: CheckStatus) {
        switch status {
        case .good: good += 1
        case .watch: watch += 1
        case .problem: problem += 1
        case .notTested: notTested += 1
        case .unavailable, .manualRequired: toCheck += 1
        case .notApplicable, .info: break
        }
    }

    public var countersText: String {
        var parts = [
            L("\(good) good", "\(good) bon\(good > 1 ? "s" : "")"),
            L("\(watch) to watch", "\(watch) à surveiller"),
            L("\(problem) problem\(problem > 1 ? "s" : "")", "\(problem) problème\(problem > 1 ? "s" : "")"),
            L("\(notTested) not tested", "\(notTested) non testé\(notTested > 1 ? "s" : "")")
        ]
        if toCheck > 0 { parts.append(L("\(toCheck) to check manually", "\(toCheck) à vérifier soi-même")) }
        return parts.joined(separator: " · ")
    }

    public var testsText: String {
        L("\(testsDone) of \(testsPlanned) tests done", "\(testsDone) test\(testsDone > 1 ? "s" : "") réalisé\(testsDone > 1 ? "s" : "") sur \(testsPlanned)")
    }
}

/// Une ligne de « Points forts » ou « À vérifier avant l'achat ».
public struct ReportPoint: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let key: String
    public let status: CheckStatus
    public let title: String
    public let detail: String?
}

/// Points forts et points à vérifier, générés à partir des mesures (correctifs §4.3).
/// Aucune promesse : un point fort n'existe que si la mesure a été faite et jugée bonne.
public enum ReportInsights {
    public static func strengths(_ r: ConditionReport, builtAt: Date? = AppBuild.date, now: Date = Date(),
                                 runningMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> [ReportPoint] {
        var points: [ReportPoint] = []
        let lock = r.measurement(MetricID.activationLock)
        // Le point fort ne dépend que du verrouillage d'activation : « aucun signal » MDM ne prouve pas
        // que le Mac n'est pas assigné à une organisation.
        if lock?.status == .good {
            // Un compte Apple encore connecté est signalé dans « À vérifier » : le point fort le rappelle en une ligne.
            let account = r.measurement(MetricID.appleAccount)
            points.append(ReportPoint(key: "locks", status: .good,
                                      title: L("No Activation Lock detected", "Aucun verrouillage d'activation détecté"),
                                      detail: account?.status == .watch
                                          ? L("In the current session. An Apple Account is still signed in: see below.", "Dans la session actuelle. Un compte Apple reste connecté : voir ci-dessous.")
                                          : L("In the current session.", "Dans la session actuelle.")))
        }
        if let health = r.measurement(MetricID.batteryHealth), health.status == .good, let percent = health.value?.intValue {
            let cycles = r.measurement(MetricID.batteryCycles)?.value?.intValue
            points.append(ReportPoint(key: "battery", status: .good,
                                      title: cycles.map { L("Battery at \(percent)% after \(Formatters.integer(Int($0))) cycles", "Batterie à \(percent) % après \(Formatters.integer(Int($0))) cycles") }
                                          ?? L("Battery at \(percent)%", "Batterie à \(percent) %"),
                                      detail: nil))
        }
        if let ssd = r.measurement(MetricID.storageHealth), ssd.status == .good {
            let wear = r.measurement(MetricID.storagePercentageUsed)?.value?.intValue
            points.append(ReportPoint(key: "ssd", status: .good,
                                      title: L("SSD in good health", "SSD en bonne santé"),
                                      detail: wear.map { L("\($0)% of its rated endurance used", "\($0) % de son endurance prévue utilisée") }))
        }
        // « Dernier macOS » : la version en cours si elle dépasse celle connue de l'app. Le point fort n'est
        // affirmé que si cette version de l'app a moins de 18 mois ; au-delà, la liste a pu vieillir et le
        // texte devient neutre.
        let reference = MacOSRelease.reference(runningMajor: runningMajor)
        if let model = r.profile.model, model.lastMacOS == nil || model.lastMacOS == reference {
            let name = MacOSRelease.name(reference)
            let isFresh = builtAt.map { now.timeIntervalSince($0) < AppBuild.freshnessLimit } ?? false
            if isFresh {
                // Mac Intel : macOS 26 est la dernière version annoncée pour eux. Dire « compatible avec le dernier macOS »
                // sans cette précision flatterait le Mac.
                let isIntel = r.profile.chip == .intel || r.profile.chip == .intelT2
                points.append(ReportPoint(key: "macos", status: .good,
                                          title: isIntel && reference == MacOSRelease.lastForIntel
                                              ? L("Runs \(name), the last version planned for Intel Macs", "Reçoit \(name), dernière version prévue pour les Mac Intel")
                                              : L("Runs the latest macOS (\(name))", "Compatible avec le dernier macOS (\(name))"),
                                          detail: nil))
            } else {
                points.append(ReportPoint(key: "macos", status: .info,
                                          title: L("Ran \(name) when this version of Aman Check was released.", "Faisait tourner \(name) à la sortie de cette version d'Aman Check."),
                                          detail: nil))
            }
        }
        let passed = r.tests.filter { $0.outcome == .passed && $0.status == .good }
        if !passed.isEmpty {
            points.append(ReportPoint(key: "tests", status: .good,
                                      title: L("Passed: ", "Réussis : ") + passed.map(\.test.title).joined(separator: ", "),
                                      detail: nil))
        }
        return points
    }

    /// Tout ce qui est `problem`, `watch`, `unavailable`, `manualRequired` ou `notTested` (spec §8.2.6).
    public static func toCheck(_ r: ConditionReport) -> [ReportPoint] {
        var points: [ReportPoint] = []
        for m in r.measurements where m.status.needsFollowUp && MetricCatalog.contains(m.id) {
            let info = MetricCatalog.info(for: m.id)
            // Détails avancés non disponibles : pas de quoi alerter l'acheteur.
            if info.level == .advanced && (m.status == .unavailable || m.status == .notTested) { continue }
            points.append(ReportPoint(key: m.id, status: m.status, title: m.label + L(": ", " : ") + m.displayText,
                                      detail: m.note ?? m.detail))
        }
        var untested: [TestID] = []
        for test in r.plannedTests {
            let result = r.result(test)
            let status = result?.status ?? .notTested
            guard status.needsFollowUp else { continue }
            if status == .notTested {
                untested.append(test)
                continue
            }
            let title = test.title + L(": ", " : ") + (result?.summary ?? status.label)
            points.append(ReportPoint(key: "test.\(test.rawValue)", status: status, title: title, detail: result?.details.first))
        }
        // Tests non réalisés : une seule ligne, pour ne pas noyer les vrais points d'attention.
        if !untested.isEmpty {
            let names = untested.map(\.title).joined(separator: ", ")
            points.append(ReportPoint(key: "tests.notTested", status: .notTested,
                                      title: untested.count == 1
                                        ? L("Test not done: \(names)", "Test non réalisé : \(names)")
                                        : L("\(untested.count) tests not done: \(names)", "\(untested.count) tests non réalisés : \(names)"),
                                      detail: L("Test them in person before buying.", "À tester sur place avant l'achat.")))
        }
        return points.sorted { $0.status.severity < $1.status.severity }
    }
}
