import Foundation
import SwiftUI
import AVFoundation
import LocalAuthentication
import AmanCore
import AmanStorageKit
import DiskHealthCore

typealias Measurement = AmanCore.Measurement

enum AppInfo {
    static let name = "Aman Check"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    /// Code source d'Aman Check.
    static let repositoryURL = URL(string: "https://github.com/MidZai/aman_check")!
    /// Page Ko-fi du projet (la même qu'Aman Disk).
    static let supportURL = URL(string: "https://ko-fi.com/midzai")!
    /// Aman Disk, l'outil frère (open source) pour aller plus loin sur le disque.
    static let amanDiskURL = URL(string: "https://github.com/MidZai/aman_disk")!
}

/// Étapes de l'analyse automatique, dans l'ordre (correctifs §4.2).
enum AnalysisStep: String, CaseIterable, Identifiable {
    case identity, locks, battery, storage, sensors, connectivity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: return L("Identity and configuration", "Identité et configuration")
        case .locks: return L("Locks", "Verrouillages")
        case .battery: return L("Battery", "Batterie")
        case .storage: return L("SSD", "SSD")
        case .sensors: return L("Fans and temperature", "Ventilateurs et température")
        case .connectivity: return L("Wi-Fi and Bluetooth", "Wi-Fi et Bluetooth")
        }
    }
}

enum StepState { case pending, running, done }

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case overview, tests, performance, report
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Check", "Contrôle")
        case .tests: return L("Guided tests", "Tests guidés")
        case .performance: return L("Performance", "Performance")
        case .report: return L("Report", "Rapport")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "checklist"
        case .tests: return "hand.tap"
        case .performance: return "speedometer"
        case .report: return "doc.text"
        }
    }
}

@MainActor
final class CheckController: ObservableObject {
    enum Phase { case welcome, analyzing, results }

    @Published var selection: SidebarItem? = .overview
    @Published private(set) var phase: Phase = .welcome
    @Published private(set) var steps: [AnalysisStep: StepState] = [:]
    @Published private(set) var profile: DeviceProfile
    @Published private(set) var measurements: [Measurement] = []
    @Published private(set) var results: [TestID: TestResult] = [:]
    /// Test de performance (§7.8) : « Non testé » tant que la personne ne l'a pas lancé.
    @Published private(set) var performance: [Measurement] = PerformanceAnalysis.notRun()
    let performanceRunner = PerformanceRunner()
    @Published private(set) var analyzedAt: Date?
    /// Aperçu affiché sur l'accueil, avant le contrôle (lectures instantanées).
    @Published private(set) var preview: [String] = []
    @Published var sellerName = ""
    @Published var wizardStart: TestID?
    @Published var singleTest: TestID?
    /// Demande de confirmation avant un nouveau contrôle qui effacerait des tests guidés déjà faits.
    @Published var rerunConfirmationShown = false

    private var reportID = ConditionReport.makeID()
    /// Début du dernier contrôle : les tests terminés avant n'appartiennent pas au rapport.
    private var analysisStartedAt: Date?

    init() {
        let simulated = DeviceProfile.simulatedIdentifier()
        let identifier = simulated ?? SystemReader.modelIdentifier
        profile = DeviceProfile.make(modelIdentifier: identifier, detected: Self.detect(), simulated: simulated != nil)
        DiagnosticLog.shared.log("profile", "\(identifier) simulé=\(simulated != nil) reconnu=\(profile.isRecognized)")
        preview = Self.quickPreview()
        if ProcessInfo.processInfo.arguments.contains("--auto-run") {
            Task { await runAnalysis() }
        }
    }

    var plannedTests: [TestID] { TestID.applicable(to: profile) }

    func measurement(_ id: String) -> Measurement? { allMeasurements.first { $0.id == id } }

    /// Analyse automatique et test de performance : ce que montre et exporte le rapport.
    var allMeasurements: [Measurement] { measurements + performance }

    func measurements(in section: MetricSection, level: MetricLevel? = nil) -> [Measurement] {
        allMeasurements.filter {
            let info = MetricCatalog.info(for: $0.id)
            return info.section == section && (level == nil || info.level == level)
        }
    }

    var report: ConditionReport {
        ConditionReport(reportID: reportID, generatedAt: analyzedAt ?? Date(), appVersion: AppInfo.version, profile: profile,
                        measurements: allMeasurements,
                        tests: TestResult.belonging(toAnalysisStartedAt: analysisStartedAt, plannedTests.compactMap { results[$0] }),
                        plannedTests: plannedTests,
                        sellerName: sellerName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sellerName)
    }

    var summary: ReportSummary { ReportSummary(report: report) }

    // MARK: Analyse automatique

    /// Nombre de tests guidés qui seraient perdus par un nouveau contrôle.
    var testsAtRisk: Int { report.tests.count }

    /// Point d'entrée de « Relancer » et ⌘R : confirme d'abord si des tests guidés seraient effacés.
    func requestRerun() {
        guard phase != .analyzing else { return }
        if phase == .results && testsAtRisk > 0 {
            rerunConfirmationShown = true
        } else {
            Task { await runAnalysis() }
        }
    }

    func runAnalysis() async {
        guard phase != .analyzing else { return }
        phase = .analyzing
        measurements = []
        reportID = ConditionReport.makeID()
        // Des tests guidés faits avant cette analyse ne disparaissent pas en silence : ils sont conservés et
        // rattachés à ce contrôle (la confirmation de « Relancer » couvre le cas d'un nouveau contrôle).
        analysisStartedAt = TestResult.analysisStart(keeping: Array(results.values), now: Date())
        steps = Dictionary(uniqueKeysWithValues: AnalysisStep.allCases.map { ($0, .pending) })

        // Identité (et lecture du SSD, dont la capacité fait partie de la configuration).
        steps[.identity] = .running
        let storage = await Task.detached(priority: .userInitiated) { StorageCollector.readInternalDisk() }.value
        let identity = await IdentityCollector.collect(profile: profile, storageCapacity: StorageCollector.capacityMeasurement(storage))
        if !profile.isSimulated {
            var detected = Self.detect()
            detected.hasT2 = identity.hasT2
            profile = DeviceProfile.make(modelIdentifier: profile.modelIdentifier, detected: detected)
        }
        measurements += identity.measurements
        // Composants attendus sur ce modèle mais non détectés : une ligne « problème » chacun (B1.1).
        measurements += profile.missingComponentMeasurements()
        steps[.identity] = .done

        steps[.locks] = .running
        measurements += await SecurityCollector.collect(profile: profile)
        steps[.locks] = .done

        steps[.battery] = .running
        measurements += await BatteryCollector.collect(profile: profile)
        steps[.battery] = .done

        steps[.storage] = .running
        measurements += StorageCollector.measurements(storage)
        steps[.storage] = .done

        steps[.sensors] = .running
        let sensors = await Task.detached(priority: .userInitiated) { SensorCollector.read() }.value
        measurements += SensorAnalysis.measurements(sensors, expectsFan: profile.hasFan)
        if let light = SensorAnalysis.ambientLightMeasurement(lux: AmbientLightSensor.readOnce(), expected: profile.hasAmbientLightSensor) {
            measurements.append(light)
        }
        steps[.sensors] = .done

        steps[.connectivity] = .running
        measurements += await ConnectivityCollector.collect()
        steps[.connectivity] = .done

        analyzedAt = Date()
        for m in measurements {
            DiagnosticLog.shared.log("mesure", "\(m.id) = \(m.displayText) [\(m.status.rawValue)] \(m.method ?? "")")
        }
        withAnimation(.easeOut(duration: 0.25)) { phase = .results }
    }

    // MARK: Tests

    func record(_ result: TestResult) {
        results[result.test] = result
        DiagnosticLog.shared.log("test", "\(result.test.rawValue) → \(result.outcome.rawValue) : \(result.summary) \(result.details.joined(separator: " | "))")
    }

    func resetTests() {
        results = [:]
    }

    // MARK: Performance

    /// Table de référence (Contents/Resources/PerformanceReference.json) ; vide si absente.
    static let performanceReference: PerformanceReference = {
        let url = Bundle.main.url(forResource: "PerformanceReference", withExtension: "json")
        return PerformanceReference(json: url.flatMap { try? Data(contentsOf: $0) })
    }()

    func runPerformance() {
        performanceRunner.start { [weak self] run in
            guard let self else { return }
            if let run {
                self.performance = PerformanceAnalysis.measurements(run, reference: Self.performanceReference, expectsFan: self.profile.hasFan)
                for m in self.performance {
                    DiagnosticLog.shared.log("performance", "\(m.id) = \(m.displayText) [\(m.status.rawValue)]")
                }
            } else {
                self.performance = PerformanceAnalysis.notRun(cancelled: true)
            }
        }
    }

    /// Mode --snapshot --performance : attend la fin du test.
    func runPerformanceAndWait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            performanceRunner.start { [weak self] run in
                if let self, let run {
                    self.performance = PerformanceAnalysis.measurements(run, reference: Self.performanceReference, expectsFan: self.profile.hasFan)
                }
                continuation.resume()
            }
        }
    }

    // MARK: Détection matérielle

    static func detect() -> DeviceProfile.Detected {
        var d = DeviceProfile.Detected()
        d.hasBattery = SystemReader.batteryProperties().map { ($0["BatteryInstalled"] as? Bool) ?? true } ?? false
        d.isAppleSilicon = SystemReader.isAppleSilicon
        let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        d.hasBuiltInCamera = !cameras.isEmpty
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        // biometryType est renseigné même si aucune empreinte n'est enregistrée (erreur biometryNotEnrolled).
        d.hasBiometrics = context.biometryType == .touchID
        return d
    }

    /// « Intel Core i9-9980HK · 32 Go · macOS 26.4.1 » : lectures instantanées (sysctl).
    static func quickPreview() -> [String] {
        var parts: [String] = []
        if let brand = SystemReader.sysctlString("machdep.cpu.brand_string") {
            parts.append(IdentityCollector.prettyCPU(brand).name)
        }
        if let bytes = SystemReader.sysctlInt("hw.memsize") {
            parts.append("\(Formatters.decimal((Double(bytes) / 1_073_741_824).rounded()))\(Formatters.unitSpace)\(L("GB", "Go"))")
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        parts.append("macOS \(v.majorVersion).\(v.minorVersion)\(v.patchVersion > 0 ? ".\(v.patchVersion)" : "")")
        return parts
    }
}
