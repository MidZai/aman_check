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

    public var isRecognized: Bool { model != nil }
    public var isLaptop: Bool { kind == .laptop }

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

        return DeviceProfile(
            modelIdentifier: modelIdentifier,
            model: model,
            isSimulated: simulated,
            kind: kind,
            chip: chip,
            hasBattery: d.hasBattery ?? isLaptop,
            hasBuiltInKeyboard: isLaptop,
            hasBuiltInTrackpad: isLaptop,
            // Tous les portables pris en charge (2018 et plus) ont un trackpad Force Touch.
            trackpadForceTouch: isLaptop,
            hasTouchBar: model?.hasTouchBar ?? false,
            hasPhysicalFunctionRow: model?.hasFunctionRow ?? isLaptop,
            hasPhysicalEscape: model?.hasPhysicalEscape ?? isLaptop,
            hasTouchID: d.hasBiometrics ?? model?.hasTouchID ?? false,
            hasBuiltInCamera: d.hasBuiltInCamera ?? model?.hasCamera ?? (isLaptop || kind == .iMac),
            // Micro intégré : portables et iMac. Mac mini / Studio / Pro n'en ont pas.
            hasBuiltInMic: isLaptop || kind == .iMac,
            // Tous les Mac ont au moins un haut-parleur interne (y compris Mac mini, Studio, Pro).
            hasInternalSpeakers: true,
            thunderboltPorts: model?.thunderboltPorts,
            hasHeadphoneJack: true,
            hasSDSlot: model?.hasSDSlot ?? false,
            hasHDMI: model?.hasHDMI ?? false,
            hasMagSafe: model?.hasMagSafe ?? false
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
