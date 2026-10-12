import Foundation
import AmanCore
import DiskHealthCore

typealias Measurement = AmanCore.Measurement

// Export du catalogue de libellés pour la page publique (cahier des charges niveau 2, §7) :
// les libellés de la page viennent de la même source que l'app, jamais recopiés à la main.
//
//   swift run AmanCatalogExport server/src/catalog.json [--sample-report server/test/fixtures/report.json]

struct LanguagePack: Encodable {
    struct Metric: Encodable {
        let label: String
        let help: String?
        let section: String
        let level: String
        let isJudged: Bool
    }
    struct Labeled: Encodable {
        let label: String
        let short: String?
    }
    struct Test: Encodable {
        let title: String
        let subtitle: String
    }

    let metrics: [String: Metric]
    let sections: [String: String]
    let statuses: [String: Labeled]
    let provenance: [String: Labeled]
    let tests: [String: Test]
    let outcomes: [String: String]
    let text: [String: String]
    let lists: [String: [String]]
    let errors: [String: String]
}

struct Catalog: Encodable {
    let comment = "Généré par AmanCatalogExport depuis AmanCore. Ne pas modifier à la main : npm run catalog."
    let procedureVersion = ConditionReport.procedureVersion
    let schemaVersion = ConditionReport.schemaVersion
    let metricOrder = MetricCatalog.orderedIDs
    let sectionOrder = MetricSection.allCases.map(\.rawValue)
    let testOrder = TestID.allCases.map(\.rawValue)
    let blockers = [MetricID.activationLock, MetricID.mdm, MetricID.virtualMachine]
    let lockIDs = [MetricID.activationLock, MetricID.appleAccount, MetricID.mdm, MetricID.firmwarePassword]
    let severity = Dictionary(uniqueKeysWithValues: CheckStatus.allCases.map { ($0.rawValue, $0.severity) })
    let languages: [String: LanguagePack]
}

func pack(_ language: AppLanguage) -> LanguagePack {
    Localization.language = language
    var metrics: [String: LanguagePack.Metric] = [:]
    for id in MetricCatalog.orderedIDs {
        let info = MetricCatalog.info(for: id)
        metrics[id] = .init(label: info.label, help: info.help, section: info.section.rawValue, level: info.level.rawValue, isJudged: info.isJudged)
    }
    let provenances: [Provenance] = [.measuredAuto, .userObserved, .derived]
    let outcomes: [TestOutcome] = [.passed, .failed, .skipped, .aborted]
    return LanguagePack(
        metrics: metrics,
        sections: Dictionary(uniqueKeysWithValues: MetricSection.allCases.map { ($0.rawValue, $0.title) }),
        statuses: Dictionary(uniqueKeysWithValues: CheckStatus.allCases.map { ($0.rawValue, .init(label: $0.label, short: nil)) }),
        provenance: Dictionary(uniqueKeysWithValues: provenances.map { ($0.rawValue, .init(label: $0.label, short: $0.shortLabel)) }),
        tests: Dictionary(uniqueKeysWithValues: TestID.allCases.map { ($0.rawValue, .init(title: $0.title, subtitle: $0.subtitle)) }),
        outcomes: Dictionary(uniqueKeysWithValues: outcomes.map { ($0.rawValue, $0.label) }),
        text: [
            "reportTitle": ReportText.title,
            "disclaimerLevel1": ReportText.disclaimer,
            "trustLevel1": ReportText.trustLevel1,
            "trustLevel2": Level2Text.trustLevel2,
            "verifiableReport": Level2Text.verifiableReport,
            "disclaimer": Level2Text.disclaimer,
            "provesTitle": Level2Text.provesTitle,
            "checkThisMacTitle": Level2Text.checkThisMacTitle,
            "checkThisMac": Level2Text.checkThisMac,
            "pdfMatch": Level2Text.pdfMatch,
            "stateValid": Level2Text.stateValid(date: "{date}"),
            "stateOld": Level2Text.stateOld,
            "stateReplaced": Level2Text.stateReplaced,
            "stateReplacedLink": Level2Text.stateReplacedLink,
            "stateWithdrawn": Level2Text.stateWithdrawn,
            "stateNotFound": Level2Text.stateNotFound,
            "stateErased": Level2Text.stateErased,
            "footerCTA": Level2Text.footerCTA,
            "linkPreview": Level2Text.linkPreview(model: "{model}", date: "{date}"),
            "sentTitle": Level2Text.sentTitle,
            "neverSentTitle": Level2Text.neverSentTitle,
            "simulatedWarning": ReportText.simulatedWarning
        ],
        lists: [
            "proves": Level2Text.proves,
            "doesNotProve": Level2Text.doesNotProve,
            "buyerChecks": Level2Text.buyerChecks,
            "sent": Level2Text.sent,
            "neverSent": Level2Text.neverSent
        ],
        errors: Dictionary(uniqueKeysWithValues: PublishError.allCases.map { ($0.rawValue, $0.message) })
    )
}

/// Rapport d'exemple encodé exactement comme l'app (fixture des tests du serveur).
func sampleReport() -> ConditionReport {
    let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true, hasBuiltInCamera: true, hasBiometrics: true, hasT2: true, isAppleSilicon: false))
    var battery = BatteryRegistry()
    battery.cycleCount = 510
    battery.designCapacity = 8790
    battery.nominalChargeCapacity = 7270
    battery.batteryInstalled = true
    let measurements: [Measurement] = [
        Measurement(id: MetricID.modelName, value: .text("MacBookPro16,1"), status: .info, provenance: .derived, display: profile.displayName),
        Measurement(id: MetricID.modelYear, value: .int(2019), status: .info, provenance: .derived, display: "2019"),
        Measurement(id: MetricID.chip, value: .text("Intel Core i9-9980HK"), status: .info, display: "Intel Core i9-9980HK", detail: "2,4 GHz"),
        Measurement(id: MetricID.ram, value: .int(32), unit: "Go", status: .info, display: "32 Go"),
        Measurement(id: MetricID.storageCapacity, value: .int(1_000_204_886_016), status: .info, display: "1 To"),
        Measurement(id: MetricID.macOS, value: .text("26.4.1"), status: .info, display: "macOS 26.4.1"),
        Measurement(id: MetricID.serial, value: .text("Q2XD"), status: .info, method: "IOPlatformSerialNumber", display: "••••Q2XD",
                    detail: "4 derniers caractères"),
        Measurement(id: MetricID.activationLock, value: .text("activation_lock_disabled"), status: .good, display: "Verrou désactivé",
                    note: "Faites tout de même effacer le Mac devant vous."),
        Measurement(id: MetricID.appleAccount, value: .int(1), status: .watch, display: "Compte connecté",
                    detail: "Un compte Apple est connecté et Localiser mon Mac est activé.",
                    note: "À faire avant la remise : se déconnecter, puis effacer le Mac."),
        Measurement(id: MetricID.mdm, value: .text("no"), status: .good, display: "Aucun signal détecté"),
        SecurityAnalysis.firmwarePassword(chip: .intelT2),
        SecurityAnalysis.virtualMachine(hvVmmPresent: 0)
    ] + BatteryAnalysis.analyze(registry: battery, power: PowerProfile(condition: "Normal", cycleCount: 510), ratedCyclesFromModel: 1000) + [
        Measurement(id: MetricID.storageHealth, value: .text("good"), status: .good, display: "En bonne santé"),
        Measurement(id: MetricID.storagePowerOnHours, value: .int(3650), unit: "h", status: .info, display: "3 650 h", detail: "≈ 5 mois sous tension"),
        Measurement(id: MetricID.storageDataWritten, value: .int(42_000_000_000_000), status: .info, display: "42 To"),
        Measurement(id: MetricID.storagePercentageUsed, value: .int(3), unit: "%", status: .good, display: "3 %"),
        Measurement(id: MetricID.wifi, value: .int(12), status: .good, display: "Fonctionnel", detail: "12 réseaux détectés à proximité"),
        Measurement(id: MetricID.bluetooth, value: .text("on"), status: .good, display: "Fonctionnel")
    ]
    let tests = [
        TestResult(test: .screen, outcome: .passed, provenance: .userObserved, summary: "Aucun défaut constaté"),
        TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "66 touches sur 66 détectées"),
        TestResult(test: .trackpad, outcome: .failed, status: .watch, provenance: .measuredAuto, summary: "5 gestes sur 6 · 100 % de la surface",
                   details: ["Non reçus : Clic forcé (appuyez plus fort)"]),
        TestResult.notTested(.camera, reason: "Ignoré par l'utilisateur")
    ]
    return ConditionReport(reportID: "AC-7K3P-Q2XD", generatedAt: Date(timeIntervalSince1970: 1_791_712_800), appVersion: "1.0.0",
                           profile: profile, measurements: measurements, tests: tests, plannedTests: TestID.applicable(to: profile),
                           sellerName: "Boutique Exemple")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: AmanCatalogExport <catalog.json> [--sample-report <report.json>]\n".utf8))
    exit(64)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let catalog = Catalog(languages: ["fr": pack(.french), "en": pack(.english)])
try encoder.encode(catalog).write(to: URL(fileURLWithPath: args[1]))
print("Catalogue écrit : \(args[1])")

if let i = args.firstIndex(of: "--sample-report"), i + 1 < args.count {
    Localization.language = .french
    try ReportCoding.encode(sampleReport()).write(to: URL(fileURLWithPath: args[i + 1]))
    print("Rapport d'exemple écrit : \(args[i + 1])")
}
