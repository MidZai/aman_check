import Foundation
import DiskHealthCore

/// Identifiants techniques des mesures. Jamais affichés : le texte vient de `MetricCatalog`.
public enum MetricID {
    // Verrouillages
    public static let activationLock = "security.activation_lock"
    public static let appleAccount = "security.apple_account"
    public static let mdm = "security.mdm"
    public static let firmwarePassword = "security.firmware_password"
    // Sécurité (Avancé)
    public static let sip = "security.sip"
    public static let fileVault = "security.filevault"
    public static let virtualMachine = "security.virtual_machine"
    public static let configProfiles = "security.config_profiles"
    public static let securityChip = "security.chip"

    // Identité
    public static let modelName = "identity.model_name"
    public static let modelIdentifier = "identity.model_identifier"
    public static let modelYear = "identity.model_year"
    public static let chip = "identity.chip"
    public static let cpuCores = "identity.cpu_cores"
    public static let gpu = "identity.gpu"
    public static let ram = "identity.ram"
    public static let storageCapacity = "identity.storage_capacity"
    public static let macOS = "identity.macos"
    public static let macOSMax = "identity.macos_max"
    public static let serial = "identity.serial"
    public static let display = "identity.display"

    // Batterie
    public static let batteryHealth = "battery.health_percent"
    public static let batteryCycles = "battery.cycles"
    public static let batteryCondition = "battery.condition"
    /// Composant que le catalogue attend sur ce modèle mais que la machine ne signale pas.
    public static let batteryPresence = "battery.presence"
    public static let cameraPresence = "hardware.camera_presence"
    public static let touchIDPresence = "hardware.touch_id_presence"
    public static let batteryDesignCapacity = "battery.design_capacity"
    public static let batteryMaxCapacity = "battery.max_capacity"
    public static let batteryCharging = "battery.is_charging"
    public static let batteryTemperature = "battery.temperature"

    // Stockage
    public static let storageHealth = "storage.health"
    public static let storagePowerOnHours = "storage.power_on_hours"
    public static let storageDataWritten = "storage.data_written"
    public static let storagePercentageUsed = "storage.percentage_used"
    public static let storageAvailableSpare = "storage.available_spare"
    public static let storageMediaErrors = "storage.media_errors"
    public static let storageTemperature = "storage.temperature"
    public static let storageModel = "storage.model"
    public static let storageInterface = "storage.interface"

    // Connectivité
    public static let wifi = "connectivity.wifi"
    public static let bluetooth = "connectivity.bluetooth"
}

public enum MetricLevel: String, Codable, Sendable {
    case essential
    case advanced
}

public enum MetricSection: String, Codable, Sendable, CaseIterable {
    case locks, identity, battery, storage, connectivity, security

    public var title: String {
        switch self {
        case .locks: return L("Locks", "Verrouillages")
        case .identity: return L("Configuration", "Configuration")
        case .battery: return L("Battery", "Batterie")
        case .storage: return L("Storage", "Stockage")
        case .connectivity: return L("Wireless", "Sans fil")
        case .security: return L("System protection", "Protection du système")
        }
    }
}

/// Libellé, aide et niveau d'affichage d'une mesure.
public struct MetricInfo: Sendable {
    public let id: String
    public let label: String
    public let help: String?
    public let level: MetricLevel
    public let section: MetricSection
    /// Faux pour les informations sans jugement : aucune pastille n'est affichée.
    public let isJudged: Bool
}

/// Catalogue des libellés (correctifs §3.3) : aucune chaîne technique n'atteint l'écran.
public enum MetricCatalog {
    public static func info(for id: String) -> MetricInfo {
        if let info = all[id] { return info }
        // Identifiant inconnu : on n'affiche jamais l'identifiant brut.
        assertionFailure("Mesure sans libellé : \(id)")
        return MetricInfo(id: id, label: L("Other information", "Autre information"), help: nil,
                          level: .advanced, section: .identity, isJudged: false)
    }

    public static func contains(_ id: String) -> Bool { all[id] != nil }

    public static var allIDs: [String] { Array(all.keys) }

    /// Identifiants dans l'ordre du catalogue (sections, puis ordre d'affichage) : sert à l'export JSON.
    public static var orderedIDs: [String] { entries.map(\.0) }

    private static func m(_ id: String, _ en: String, _ fr: String, _ section: MetricSection,
                          _ level: MetricLevel, judged: Bool,
                          help: (String, String)? = nil) -> (String, MetricInfo) {
        (id, MetricInfo(id: id, label: L(en, fr), help: help.map { L($0.0, $0.1) },
                        level: level, section: section, isJudged: judged))
    }

    // Construit à la demande : les libellés suivent la langue courante.
    private static var all: [String: MetricInfo] {
        Dictionary(uniqueKeysWithValues: entries)
    }

    private static var entries: [(String, MetricInfo)] {
        [
            m(MetricID.activationLock, "iCloud Activation Lock", "Verrouillage d'activation iCloud", .locks, .essential, judged: true,
              help: ("Linked to the owner's Apple Account and Find My. A locked Mac cannot be set up by anyone else after it is erased.",
                     "Lié au compte Apple du propriétaire et à Localiser. Un Mac verrouillé ne peut pas être configuré par quelqu'un d'autre après effacement.")),
            m(MetricID.appleAccount, "Apple Account signed in", "Compte Apple connecté", .locks, .essential, judged: true,
              help: ("Apple Account (iCloud) signed in in the current session. It drives Find My and Activation Lock, so the seller must sign out and erase the Mac before handing it over. Only the number of accounts is read, never the account itself.",
                     "Compte Apple (iCloud) connecté dans la session actuelle. C'est lui qui pilote Localiser et le verrouillage d'activation : le vendeur doit se déconnecter et effacer le Mac avant la remise. Seul le nombre de comptes est lu, jamais l'identifiant.")),
            m(MetricID.mdm, "Company management (MDM)", "Gestion par une entreprise (MDM)", .locks, .essential, judged: true,
              help: ("A Mac owned by a company or a school can be locked or wiped remotely by its organization.",
                     "Un Mac appartenant à une entreprise ou à une école peut être verrouillé ou effacé à distance par son organisation.")),
            m(MetricID.firmwarePassword, "Firmware password", "Mot de passe firmware", .locks, .essential, judged: true,
              help: ("A password set in the Mac's firmware blocks startup from another disk and recovery mode.",
                     "Un mot de passe enregistré dans le firmware bloque le démarrage sur un autre disque et le mode de récupération.")),
            m(MetricID.sip, "System Integrity Protection (SIP)", "Protection de l'intégrité du système (SIP)", .security, .advanced, judged: true,
              help: ("Enabled on every Mac by default. Turned off, it is a sign that the system has been tinkered with.",
                     "Activée par défaut sur tous les Mac. Désactivée, c'est un signe de modification du système.")),
            m(MetricID.fileVault, "FileVault encryption", "Chiffrement FileVault", .security, .advanced, judged: false,
              help: ("Disk encryption. Neither good nor bad: it is erased with the Mac.",
                     "Chiffrement du disque. Ni bon ni mauvais : il disparaît avec l'effacement du Mac.")),
            m(MetricID.virtualMachine, "Virtual machine", "Machine virtuelle", .security, .advanced, judged: true,
              help: ("A report generated inside a virtual machine does not describe a real Mac.",
                     "Un rapport généré dans une machine virtuelle ne décrit pas un vrai Mac.")),
            m(MetricID.configProfiles, "Configuration profiles", "Profils de configuration", .security, .advanced, judged: false),
            m(MetricID.securityChip, "Security chip", "Puce de sécurité", .security, .advanced, judged: false),

            m(MetricID.modelName, "Model", "Modèle", .identity, .essential, judged: false),
            m(MetricID.modelIdentifier, "Model identifier", "Identifiant du modèle", .identity, .advanced, judged: false),
            m(MetricID.modelYear, "Model release year", "Année de commercialisation du modèle", .identity, .essential, judged: false,
              help: ("Year the model went on sale, not the manufacturing date of this Mac (which recent serial numbers no longer reveal).",
                     "Année de sortie du modèle, et non la date de fabrication de ce Mac (que les numéros de série récents ne révèlent plus).")),
            m(MetricID.chip, "Processor", "Processeur", .identity, .essential, judged: false),
            m(MetricID.cpuCores, "Cores", "Cœurs", .identity, .essential, judged: false),
            m(MetricID.gpu, "Graphics", "Graphisme", .identity, .essential, judged: false),
            m(MetricID.ram, "Memory (RAM)", "Mémoire (RAM)", .identity, .essential, judged: false),
            m(MetricID.storageCapacity, "Storage", "Stockage", .identity, .essential, judged: false),
            m(MetricID.macOS, "Installed macOS", "macOS installé", .identity, .essential, judged: false),
            m(MetricID.macOSMax, "Latest supported macOS", "macOS maximal supporté", .identity, .essential, judged: false,
              help: ("Most recent version of macOS Apple provides for this model.",
                     "Version de macOS la plus récente qu'Apple propose pour ce modèle.")),
            m(MetricID.serial, "Serial number", "N° de série", .identity, .essential, judged: false,
              help: ("Only the last 4 characters are shown. The buyer can check the full number on checkcoverage.apple.com.",
                     "Seuls les 4 derniers caractères sont affichés. L'acheteur peut vérifier le numéro complet sur checkcoverage.apple.com.")),
            m(MetricID.display, "Display", "Écran", .identity, .essential, judged: false),

            m(MetricID.batteryHealth, "Battery capacity", "Capacité de la batterie", .battery, .essential, judged: true,
              help: ("Charge the battery can hold today, compared with when it was new.",
                     "Charge que la batterie peut contenir aujourd'hui, comparée à celle d'origine.")),
            m(MetricID.batteryCycles, "Charge cycles", "Cycles de charge", .battery, .essential, judged: true,
              help: ("One cycle = 100% of the battery used, possibly over several days.",
                     "Un cycle = 100 % de la batterie utilisés, éventuellement sur plusieurs jours.")),
            m(MetricID.batteryCondition, "Condition reported by macOS", "État indiqué par macOS", .battery, .essential, judged: true),
            m(MetricID.batteryPresence, "Battery", "Batterie", .battery, .essential, judged: true,
              help: ("This model ships with a battery, but the Mac does not report one.",
                     "Ce modèle est livré avec une batterie, mais le Mac n'en signale aucune.")),
            m(MetricID.cameraPresence, "Built-in camera", "Caméra intégrée", .identity, .essential, judged: true,
              help: ("This model has a built-in camera, but the Mac does not report one.",
                     "Ce modèle a une caméra intégrée, mais le Mac n'en signale aucune.")),
            m(MetricID.touchIDPresence, "Touch ID", "Touch ID", .identity, .essential, judged: true,
              help: ("This model has a Touch ID sensor, but the Mac does not report one.",
                     "Ce modèle a un capteur Touch ID, mais le Mac n'en signale aucun.")),
            m(MetricID.batteryDesignCapacity, "Original capacity", "Capacité d'origine", .battery, .advanced, judged: false),
            m(MetricID.batteryMaxCapacity, "Current full-charge capacity", "Capacité actuelle à pleine charge", .battery, .advanced, judged: false),
            m(MetricID.batteryCharging, "Power", "Alimentation", .battery, .advanced, judged: false),
            m(MetricID.batteryTemperature, "Battery temperature", "Température de la batterie", .battery, .advanced, judged: false),

            m(MetricID.storageHealth, "SSD health", "Santé du SSD", .storage, .essential, judged: true,
              help: ("Status reported by the SSD itself (S.M.A.R.T.), read with the Aman Disk engine.",
                     "État déclaré par le SSD lui-même (S.M.A.R.T.), lu avec le moteur d'Aman Disk.")),
            m(MetricID.storagePowerOnHours, "SSD power-on hours", "Heures de fonctionnement du SSD", .storage, .essential, judged: false,
              help: ("Time the SSD has been powered on. This is not the age of the Mac.",
                     "Temps pendant lequel le SSD a été sous tension. Ce n'est pas l'âge du Mac.")),
            m(MetricID.storageDataWritten, "Data written to the SSD", "Données écrites sur le SSD", .storage, .essential, judged: false,
              help: ("Total amount written to the SSD since it was made: the main cause of SSD wear.",
                     "Volume total écrit sur le SSD depuis sa fabrication : principal facteur d'usure.")),
            m(MetricID.storagePercentageUsed, "SSD wear", "Usure du SSD", .storage, .essential, judged: true,
              help: ("Share of the rated endurance already used, as reported by the SSD.",
                     "Part de l'endurance prévue déjà consommée, selon le SSD.")),
            m(MetricID.storageAvailableSpare, "SSD spare capacity", "Réserve du SSD", .storage, .advanced, judged: true),
            m(MetricID.storageMediaErrors, "Data errors", "Erreurs de données", .storage, .advanced, judged: true),
            m(MetricID.storageTemperature, "SSD temperature", "Température du SSD", .storage, .advanced, judged: false),
            m(MetricID.storageModel, "SSD model", "Modèle du SSD", .storage, .advanced, judged: false),
            m(MetricID.storageInterface, "Interface", "Interface", .storage, .advanced, judged: false),

            m(MetricID.wifi, "Wi-Fi", "Wi-Fi", .connectivity, .essential, judged: true),
            m(MetricID.bluetooth, "Bluetooth", "Bluetooth", .connectivity, .essential, judged: true)
        ]
    }
}
