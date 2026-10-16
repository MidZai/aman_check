import Foundation
import DiskHealthCore

/// Capacités de la machine contrôlée : décide quels tests et quelles sections existent
/// (correctifs §6.0). Un test n'apparaît que si la capacité existe.
public struct DeviceProfile: Codable, Sendable, Equatable {
    public let modelIdentifier: String
    /// Fiche du catalogue ; `nil` : modèle non reconnu (profil générique prudent).
    public let model: MacModel?
    /// Profil simulé avec `--simulate-model` : seules les données du catalogue sont utilisées.
    public let isSimulated: Bool

    public let kind: MacKind
    public let chip: ChipFamily?
    public let hasBattery: Bool
    public let hasBuiltInKeyboard: Bool
    public let hasBuiltInTrackpad: Bool
    public let trackpadForceTouch: Bool
    public let hasTouchBar: Bool
    public let hasPhysicalFunctionRow: Bool
    public let hasPhysicalEscape: Bool
    public let hasTouchID: Bool
    public let hasBuiltInCamera: Bool
    public let hasBuiltInMic: Bool
    public let hasInternalSpeakers: Bool
    public let thunderboltPorts: Int?
    public let hasHeadphoneJack: Bool
    public let hasSDSlot: Bool
    public let hasHDMI: Bool
    public let hasMagSafe: Bool
    /// Composants que le catalogue attend sur ce modèle et que la machine ne signale pas (B1.1) :
    /// ils restent dans le profil, mais leur test guidé n'est pas proposé et le rapport les signale.
    /// Optionnel pour lire les rapports enregistrés avant son ajout.
    public var missingComponents: [MissingComponent]? = nil

    public var isRecognized: Bool { model != nil }
    /// Portables et iMac ; Mac mini, Mac Studio et Mac Pro n'ont pas d'écran intégré.
    public var hasBuiltInDisplay: Bool { isLaptop || kind == .iMac }

    public enum MissingComponent: String, Codable, Sendable, CaseIterable {
        case battery, camera, touchID

        public var metricID: String {
            switch self {
            case .battery: return MetricID.batteryPresence
            case .camera: return MetricID.cameraPresence
            case .touchID: return MetricID.touchIDPresence
            }
        }
    }

    public func isMissing(_ component: MissingComponent) -> Bool {
        missingComponents?.contains(component) ?? false
    }

    /// Une ligne « problème » par composant attendu mais non détecté : une pièce absente n'est jamais
    /// une simple absence de test.
    public func missingComponentMeasurements(now: Date = Date()) -> [Measurement] {
        (missingComponents ?? []).map { component in
            Measurement(id: component.metricID, value: .text("missing"), status: .problem, method: nil, collectedAt: now,
                        display: L("Expected on this model but not detected.", "Attendu sur ce modèle mais non détecté."),
                        note: L("The part may be disconnected, faulty or replaced by a non-genuine one.",
                                "La pièce peut être débranchée, défectueuse ou remplacée par une pièce non d'origine."))
        }
    }
    public var isLaptop: Bool { kind == .laptop }

    // Capteurs (spec §6.6). Calculés plutôt qu'enregistrés : les rapports déjà enregistrés se relisent tels quels.
    /// Capteur de fermeture du capot : portables.
    public var hasLid: Bool { isLaptop }
    /// Capteur de luminosité ambiante : portables et iMac (près de la caméra).
    public var hasAmbientLightSensor: Bool { isLaptop || kind == .iMac }
    /// Clavier rétroéclairé : tous les portables du catalogue (2016 et suivants).
    public var hasKeyboardBacklight: Bool { isLaptop }
    /// Ventilateur : tous les Mac du catalogue sauf les MacBook Air Apple Silicon et le MacBook 12 pouces.
    /// `nil` : modèle non reconnu.
    public var hasFan: Bool? {
        guard let model else { return nil }
        if model.family == "MacBook" { return false }
        if model.family == "MacBook Air" && model.chip == .appleSilicon { return false }
        return true
    }

    /// Nom commercial, ou l'identifiant brut si le modèle n'est pas reconnu.
    public var displayName: String {
        model?.displayName ?? modelIdentifier
    }

    /// Ce que la machine a réellement, lu sur le système (ignoré en simulation).
    public struct Detected: Sendable {
        public var hasBattery: Bool?
        public var hasBuiltInCamera: Bool?
        public var hasBiometrics: Bool?
        public var hasT2: Bool?
        public var isAppleSilicon: Bool?

        public init(hasBattery: Bool? = nil, hasBuiltInCamera: Bool? = nil, hasBiometrics: Bool? = nil,
                    hasT2: Bool? = nil, isAppleSilicon: Bool? = nil) {
            self.hasBattery = hasBattery
            self.hasBuiltInCamera = hasBuiltInCamera
            self.hasBiometrics = hasBiometrics
            self.hasT2 = hasT2
            self.isAppleSilicon = isAppleSilicon
        }
    }

    /// Profil à partir de l'identifiant (`hw.model`), du catalogue et des détections.
    /// Les détections l'emportent sur le catalogue quand elles existent (ex. Touch ID présent).
    public static func make(modelIdentifier: String, detected: Detected = Detected(), simulated: Bool = false) -> DeviceProfile {
        let model = MacModelCatalog.model(for: modelIdentifier)
        let d = simulated ? Detected() : detected

        let kind: MacKind = model?.kind ?? guessKind(modelIdentifier, hasBattery: d.hasBattery)
        let isLaptop = kind == .laptop
        let chip: ChipFamily? = model?.chip ?? {
            if d.isAppleSilicon == true { return .appleSilicon }
            if d.hasT2 == true { return .intelT2 }
            if d.isAppleSilicon == false { return .intel }
            return nil
        }()

        // Modèle reconnu : une détection négative ne retire pas le composant, elle le signale (B1.1).
        var missing: [MissingComponent] = []
        if let model {
            if model.kind == .laptop && d.hasBattery == false { missing.append(.battery) }
            if model.hasCamera && d.hasBuiltInCamera == false { missing.append(.camera) }
            if model.hasTouchID && d.hasBiometrics == false { missing.append(.touchID) }
        }
        let expectedBattery = model.map { $0.kind == .laptop } ?? isLaptop

        return DeviceProfile(
            modelIdentifier: modelIdentifier,
            model: model,
            isSimulated: simulated,
            kind: kind,
            chip: chip,
            hasBattery: missing.contains(.battery) ? expectedBattery : (d.hasBattery ?? isLaptop),
            hasBuiltInKeyboard: isLaptop,
            hasBuiltInTrackpad: isLaptop,
            // Tous les portables pris en charge (2018 et plus) ont un trackpad Force Touch.
            trackpadForceTouch: isLaptop,
            hasTouchBar: model?.hasTouchBar ?? false,
            hasPhysicalFunctionRow: model?.hasFunctionRow ?? isLaptop,
            hasPhysicalEscape: model?.hasPhysicalEscape ?? isLaptop,
            hasTouchID: missing.contains(.touchID) ? true : (d.hasBiometrics ?? model?.hasTouchID ?? false),
            hasBuiltInCamera: missing.contains(.camera) ? true : (d.hasBuiltInCamera ?? model?.hasCamera ?? (isLaptop || kind == .iMac)),
            // Micro intégré : portables et iMac. Mac mini / Studio / Pro n'en ont pas.
            hasBuiltInMic: isLaptop || kind == .iMac,
            // Tous les Mac ont au moins un haut-parleur interne (y compris Mac mini, Studio, Pro).
            hasInternalSpeakers: true,
            thunderboltPorts: model?.thunderboltPorts,
            hasHeadphoneJack: true,
            hasSDSlot: model?.hasSDSlot ?? false,
            hasHDMI: model?.hasHDMI ?? false,
            hasMagSafe: model?.hasMagSafe ?? false,
            missingComponents: missing.isEmpty ? nil : missing
        )
    }

    /// Modèle inconnu : déduction prudente d'après le préfixe de l'identifiant.
    static func guessKind(_ identifier: String, hasBattery: Bool?) -> MacKind {
        if identifier.hasPrefix("MacBook") { return .laptop }
        if identifier.hasPrefix("iMac") { return .iMac }
        if identifier.hasPrefix("Macmini") { return .mini }
        if identifier.hasPrefix("MacPro") { return .pro }
        // Identifiants récents (« Mac16,1 ») : on ne sait pas, sauf si une batterie est présente.
        if hasBattery == true { return .laptop }
        return .unknown
    }

    /// Argument de lancement `--simulate-model Macmini9,1` (correctifs §6.0, débogage).
    public static func simulatedIdentifier(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "--simulate-model"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
