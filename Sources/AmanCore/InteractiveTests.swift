import Foundation
import DiskHealthCore

/// Tests guidés (spec §7). L'ordre est celui de l'assistant.
public enum TestID: String, Codable, Sendable, CaseIterable, Identifiable {
    case screen, keyboard, touchBar, trackpad, speakers, microphone, camera, touchID, ports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screen: return L("Display", "Écran")
        case .keyboard: return L("Keyboard", "Clavier")
        case .touchBar: return "Touch Bar"
        case .trackpad: return L("Trackpad", "Trackpad")
        case .speakers: return L("Speakers", "Haut-parleurs")
        case .microphone: return L("Microphone", "Micro")
        case .camera: return L("Camera", "Caméra")
        case .touchID: return "Touch ID"
        case .ports: return L("Ports", "Ports et connecteurs")
        }
    }

    public var subtitle: String {
        switch self {
        case .screen: return L("Dead pixels, stains, uneven backlight", "Pixels morts, taches, rétroéclairage inégal")
        case .keyboard: return L("Every key, one by one", "Chaque touche, une par une")
        case .touchBar: return L("Display and touch, end to end", "Affichage et toucher, d'un bout à l'autre")
        case .trackpad: return L("Clicks, gestures, Force Touch, whole surface", "Clics, gestes, Force Touch, toute la surface")
        case .speakers: return L("Left, right, crackling", "Gauche, droite, grésillements")
        case .microphone: return L("Level and recording", "Niveau et enregistrement")
        case .camera: return L("Live picture", "Image en direct")
        case .touchID: return L("Fingerprint reader", "Lecteur d'empreintes")
        case .ports: return L("USB-C, charging, video, headphones", "USB-C, charge, vidéo, casque")
        }
    }

    public var symbolName: String {
        switch self {
        case .screen: return "display"
        case .keyboard: return "keyboard"
        case .touchBar: return "rectangle.inset.filled"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .speakers: return "speaker.wave.2"
        case .microphone: return "mic"
        case .camera: return "camera"
        case .touchID: return "touchid"
        case .ports: return "cable.connector"
        }
    }

    /// Les tests qui ont un sens sur cette machine (correctifs §6.0).
    public static func applicable(to profile: DeviceProfile) -> [TestID] {
        allCases.filter { test in
            switch test {
            case .screen: return true
            case .keyboard: return profile.hasBuiltInKeyboard
            case .touchBar: return profile.hasTouchBar
            case .trackpad: return profile.hasBuiltInTrackpad
            case .speakers: return profile.hasInternalSpeakers
            case .microphone: return profile.hasBuiltInMic
            case .camera: return profile.hasBuiltInCamera && !profile.isMissing(.camera)
            case .touchID: return profile.hasTouchID && !profile.isMissing(.touchID)
            case .ports: return true
            }
        }
    }
}

/// Fin d'un test : Réussi · Échoué · Ignoré · Interrompu.
public enum TestOutcome: String, Codable, Sendable {
    case passed, failed, skipped, aborted

    public var label: String {
        switch self {
        case .passed: return L("Passed", "Réussi")
        case .failed: return L("Failed", "Échoué")
        case .skipped: return L("Skipped", "Ignoré")
        case .aborted: return L("Interrupted", "Interrompu")
        }
    }
}

public struct TestResult: Codable, Sendable, Equatable, Identifiable {
    public var id: TestID { test }
    public let test: TestID
    public let outcome: TestOutcome
    /// Verdict affiché. Ignoré ou interrompu = « Non testé », jamais « Échoué ».
    public let status: CheckStatus
    public let provenance: Provenance
    /// Résumé d'une ligne (« 65 touches sur 65 détectées »).
    public let summary: String
    /// Détails (touches non détectées, ports testés…), section Avancé.
    public let details: [String]
    public let completedAt: Date

    public init(test: TestID, outcome: TestOutcome, status: CheckStatus? = nil, provenance: Provenance,
                summary: String, details: [String] = [], completedAt: Date = Date()) {
        self.test = test
        self.outcome = outcome
        switch outcome {
        case .skipped, .aborted:
            self.status = .notTested
        case .passed:
            self.status = status ?? .good
        case .failed:
            self.status = status ?? .problem
        }
        self.provenance = provenance
        self.summary = summary
        self.details = details
        self.completedAt = completedAt
    }

    public static func notTested(_ test: TestID, reason: String, aborted: Bool = false) -> TestResult {
        TestResult(test: test, outcome: aborted ? .aborted : .skipped, provenance: .userObserved, summary: reason)
    }
}

public extension TestResult {
    /// Tests rattachés à un contrôle : seuls ceux terminés depuis son lancement.
    /// Un rapport (surtout publié) ne doit jamais porter des tests antérieurs au contrôle.
    static func belonging(toAnalysisStartedAt start: Date?, _ results: [TestResult]) -> [TestResult] {
        guard let start else { return [] }
        return results.filter { $0.completedAt >= start }
    }
}
