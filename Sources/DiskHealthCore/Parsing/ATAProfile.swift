import Foundation

public enum ATARole: Equatable {
    case temperature
    case powerOnHours
    case powerCycles
    case unsafeShutdowns
    case hostWritesBytes(multiplier: UInt64)
    case hostReadsBytes(multiplier: UInt64)
    case lifeRemainingPercentNormalized
    case reallocated
    case pending
    case uncorrectable
    case none
}

public struct AttributeOverride: Equatable {
    public let name: String
    public let explanation: String
    public let role: ATARole
}

public struct ATAProfile {
    public let name: String
    public let matches: (String) -> Bool
    public let attributes: [UInt8: AttributeOverride]
}

public enum ATACatalog {
    public static let genericAttributes: [UInt8: AttributeOverride] = [
        0x01: AttributeOverride(name: L("Read error rate", "Taux d'erreurs de lecture"), explanation: L("Errors encountered while reading. The raw value can't be compared across manufacturers.", "Erreurs rencontrées lors de la lecture. La valeur brute n'est pas comparable d'un fabricant à l'autre."), role: .none),
        0x03: AttributeOverride(name: L("Spin-up time", "Temps de démarrage du moteur"), explanation: L("Time the platters take to reach full speed (hard drives).", "Temps nécessaire aux plateaux pour atteindre leur vitesse (disques durs)."), role: .none),
        0x04: AttributeOverride(name: L("Start/stop count", "Démarrages et arrêts du moteur"), explanation: L("Number of spindle starts (hard drives).", "Nombre de démarrages du moteur (disques durs)."), role: .none),
        0x05: AttributeOverride(name: L("Reallocated sectors", "Secteurs réalloués"), explanation: L("Bad sectors replaced by spare sectors. A rising value means the media is degrading.", "Secteurs défectueux remplacés par des secteurs de réserve. Une valeur qui augmente indique une dégradation du support."), role: .reallocated),
        0x07: AttributeOverride(name: L("Seek error rate", "Taux d'erreurs de positionnement"), explanation: L("Head positioning errors (hard drives). Raw value is manufacturer-specific.", "Erreurs de positionnement des têtes (disques durs). Valeur brute propre au fabricant."), role: .none),
        0x09: AttributeOverride(name: L("Power-on hours", "Heures d'allumage"), explanation: L("Total time the drive has been powered on.", "Durée totale de fonctionnement du disque."), role: .powerOnHours),
        0x0A: AttributeOverride(name: L("Spin retry count", "Tentatives de démarrage"), explanation: L("Retries needed to spin up the motor (hard drives).", "Nouvelles tentatives nécessaires pour démarrer le moteur (disques durs)."), role: .none),
        0x0C: AttributeOverride(name: L("Power cycles", "Cycles d'allumage"), explanation: L("Number of times the drive was powered on.", "Nombre de mises sous tension du disque."), role: .powerCycles),
        0xAB: AttributeOverride(name: L("Program failures", "Échecs de programmation"), explanation: L("Write failures in flash memory cells.", "Échecs d'écriture dans les cellules de mémoire flash."), role: .none),
        0xAC: AttributeOverride(name: L("Erase failures", "Échecs d'effacement"), explanation: L("Erase failures in flash memory cells.", "Échecs d'effacement des cellules de mémoire flash."), role: .none),
        0xAD: AttributeOverride(name: L("Wear leveling", "Nivellement de l'usure"), explanation: L("Flash cell wear indicator. Interpretation is manufacturer-specific.", "Indicateur de l'usure des cellules de mémoire flash. Interprétation propre au fabricant."), role: .none),
        0xAE: AttributeOverride(name: L("Unexpected power losses", "Pertes d'alimentation inattendues"), explanation: L("Power cuts without a normal shutdown.", "Coupures de courant sans arrêt normal."), role: .unsafeShutdowns),
        0xB1: AttributeOverride(name: L("Wear leveling", "Nivellement de l'usure"), explanation: L("On many SSDs, the normalized value shows the estimated remaining life.", "Sur de nombreux SSD, la valeur normalisée indique la durée de vie restante estimée."), role: .none),
        0xB3: AttributeOverride(name: L("Used reserve blocks", "Blocs de réserve utilisés"), explanation: L("Spare blocks already used to replace worn-out blocks.", "Blocs de réserve déjà utilisés pour remplacer des blocs usés."), role: .none),
        0xB5: AttributeOverride(name: L("Program failures", "Échecs de programmation"), explanation: L("Write failures in flash memory.", "Échecs d'écriture dans la mémoire flash."), role: .none),
        0xB6: AttributeOverride(name: L("Erase failures", "Échecs d'effacement"), explanation: L("Erase failures in flash memory.", "Échecs d'effacement dans la mémoire flash."), role: .none),
        0xB7: AttributeOverride(name: L("Interface downshifts", "Rétrogradations de l'interface"), explanation: L("Number of times the SATA link had to lower its speed.", "Nombre de fois où la liaison SATA a dû réduire sa vitesse."), role: .none),
        0xB8: AttributeOverride(name: L("End-to-end errors", "Erreurs de bout en bout"), explanation: L("Transfer errors detected between the cache and the media.", "Erreurs de transfert détectées entre le cache et le support."), role: .none),
        0xBB: AttributeOverride(name: L("Reported uncorrectable errors", "Erreurs non corrigibles signalées"), explanation: L("Read errors the drive could not correct.", "Erreurs de lecture que le disque n'a pas pu corriger."), role: .uncorrectable),
        0xBE: AttributeOverride(name: L("Temperature (airflow)", "Température (flux d'air)"), explanation: L("Temperature measured by the drive.", "Température mesurée par le disque."), role: .temperature),
        0xC0: AttributeOverride(name: L("Unsafe shutdowns", "Arrêts non propres"), explanation: L("Power cuts without a normal shutdown (or emergency head retracts on a hard drive).", "Coupures d'alimentation sans arrêt normal (ou rétractions d'urgence des têtes sur un disque dur)."), role: .unsafeShutdowns),
        0xC1: AttributeOverride(name: L("Load/unload cycles", "Cycles de chargement des têtes"), explanation: L("Number of head load/unload cycles (hard drives).", "Nombre de chargements et déchargements des têtes (disques durs)."), role: .none),
        0xC2: AttributeOverride(name: L("Temperature", "Température"), explanation: L("Drive temperature.", "Température du disque."), role: .temperature),
        0xC3: AttributeOverride(name: L("ECC-corrected errors", "Erreurs corrigées par ECC"), explanation: L("Errors fixed by error correction. Manufacturer-specific value.", "Erreurs corrigées par le code de correction. Valeur propre au fabricant."), role: .none),
        0xC4: AttributeOverride(name: L("Reallocation events", "Événements de réallocation"), explanation: L("Number of reallocation operations performed.", "Nombre d'opérations de réallocation effectuées."), role: .none),
        0xC5: AttributeOverride(name: L("Pending sectors", "Secteurs en attente"), explanation: L("Unstable sectors waiting to be reallocated. Any non-zero value is a reason to back up soon.", "Secteurs instables en attente de réallocation. Une valeur non nulle mérite une sauvegarde rapide."), role: .pending),
        0xC6: AttributeOverride(name: L("Uncorrectable sectors", "Secteurs non corrigibles"), explanation: L("Unreadable sectors found during offline scans.", "Secteurs illisibles détectés lors des vérifications hors ligne."), role: .uncorrectable),
        0xC7: AttributeOverride(name: L("Interface CRC errors", "Erreurs CRC de l'interface"), explanation: L("Transmission errors on the link. Usually caused by the cable or connection, rarely by the media itself.", "Erreurs de transmission sur la liaison. Souvent liées à la connexion, rarement au support lui-même."), role: .none),
        0xE7: AttributeOverride(name: L("SSD life remaining", "Durée de vie restante du SSD"), explanation: L("Remaining life estimated by the manufacturer.", "Durée de vie restante estimée par le fabricant."), role: .lifeRemainingPercentNormalized),
        0xE8: AttributeOverride(name: L("Available spare", "Réserve disponible"), explanation: L("Share of spare blocks still available.", "Part de la réserve de blocs encore disponible."), role: .none),
        0xE9: AttributeOverride(name: L("Media wearout indicator", "Indicateur d'usure du support"), explanation: L("Flash memory wear; the normalized value goes down with use.", "Usure de la mémoire flash ; la valeur normalisée diminue avec l'usage."), role: .lifeRemainingPercentNormalized),
        0xF1: AttributeOverride(name: L("Total data written", "Total des données écrites"), explanation: L("Total amount written by the computer.", "Volume total écrit par l'ordinateur."), role: .hostWritesBytes(multiplier: 512)),
        0xF2: AttributeOverride(name: L("Total data read", "Total des données lues"), explanation: L("Total amount read by the computer.", "Volume total lu par l'ordinateur."), role: .hostReadsBytes(multiplier: 512))
    ]

    public static let genericProfile = ATAProfile(
        name: "GenericATA",
        matches: { _ in true },
        attributes: [:]
    )

    // Attribute names cross-checked with smartmontools drivedb.h and real smartctl output.
    public static let appleSMFamilyProfile = ATAProfile(
        name: "AppleSMFamily",
        matches: { model in
            model.range(of: "^APPLE SSD (SD|SM|TS)\\d{4}[EFG]$", options: .regularExpression) != nil
        },
        attributes: [
            0x01: AttributeOverride(name: genericAttributes[0x01]!.name, explanation: genericAttributes[0x01]!.explanation + L("\n\nTechnical name: Raw_Read_Error_Rate", "\n\nNom technique : Raw_Read_Error_Rate"), role: .none),
            0x05: AttributeOverride(name: genericAttributes[0x05]!.name, explanation: genericAttributes[0x05]!.explanation + L("\n\nTechnical name: Reallocated_Sector_Ct", "\n\nNom technique : Reallocated_Sector_Ct"), role: .reallocated),
            0x09: AttributeOverride(name: genericAttributes[0x09]!.name, explanation: genericAttributes[0x09]!.explanation + L("\n\nTechnical name: Power_On_Hours", "\n\nNom technique : Power_On_Hours"), role: .powerOnHours),
            0x0C: AttributeOverride(name: genericAttributes[0x0C]!.name, explanation: genericAttributes[0x0C]!.explanation + L("\n\nTechnical name: Power_Cycle_Count", "\n\nNom technique : Power_Cycle_Count"), role: .powerCycles),
            0xA9: AttributeOverride(name: L("Vendor-specific attribute", "Attribut propre au fabricant"), explanation: L("Attribute specific to this model. Its meaning isn't publicly documented.\n\nTechnical name: Unknown_Apple_Attrib", "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement.\n\nNom technique : Unknown_Apple_Attrib"), role: .none),
            0xAD: AttributeOverride(name: L("Wear leveling", "Nivellement de l'usure"), explanation: L("Media wear indicator.\n\nTechnical name: Wear_Leveling_Count", "Indicateur d'usure du support.\n\nNom technique : Wear_Leveling_Count"), role: .none),
            0xAE: AttributeOverride(name: L("Total data read", "Total des données lues"), explanation: L("Total data read by the computer.\n\nTechnical name: Host_Reads_MiB", "Total des données lues par l'ordinateur.\n\nNom technique : Host_Reads_MiB"), role: .hostReadsBytes(multiplier: 1048576)),
            0xAF: AttributeOverride(name: L("Total data written", "Total des données écrites"), explanation: L("Total data written by the computer.\n\nTechnical name: Host_Writes_MiB", "Total des données écrites par l'ordinateur.\n\nNom technique : Host_Writes_MiB"), role: .hostWritesBytes(multiplier: 1048576)),
            0xC0: AttributeOverride(name: genericAttributes[0xC0]!.name, explanation: genericAttributes[0xC0]!.explanation + L("\n\nTechnical name: Power-Off_Retract_Count", "\n\nNom technique : Power-Off_Retract_Count"), role: .unsafeShutdowns),
            0xC2: AttributeOverride(name: genericAttributes[0xC2]!.name, explanation: genericAttributes[0xC2]!.explanation + L("\n\nTechnical name: Temperature_Celsius", "\n\nNom technique : Temperature_Celsius"), role: .temperature),
            0xC5: AttributeOverride(name: genericAttributes[0xC5]!.name, explanation: genericAttributes[0xC5]!.explanation + L("\n\nTechnical name: Current_Pending_Sector", "\n\nNom technique : Current_Pending_Sector"), role: .pending),
            0xC7: AttributeOverride(name: genericAttributes[0xC7]!.name, explanation: genericAttributes[0xC7]!.explanation + L("\n\nTechnical name: UDMA_CRC_Error_Count", "\n\nNom technique : UDMA_CRC_Error_Count"), role: .none),
            0xF0: AttributeOverride(name: L("Vendor-specific attribute", "Attribut propre au fabricant"), explanation: L("Attribute specific to this model. Its meaning isn't publicly documented.\n\nTechnical name: Unknown_SSD_Attribute", "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement.\n\nNom technique : Unknown_SSD_Attribute"), role: .none)
        ]
    )
    
    public static let samsungProfile = ATAProfile(
        name: "Samsung",
        matches: { model in model.starts(with: "Samsung") },
        attributes: [
            0xB1: AttributeOverride(name: L("Wear leveling", "Nivellement de l'usure"), explanation: L("On many SSDs, the normalized value shows the estimated remaining life.", "Sur de nombreux SSD, la valeur normalisée indique la durée de vie restante estimée."), role: .lifeRemainingPercentNormalized)
        ]
    )


    public static let profiles = [appleSMFamilyProfile, samsungProfile] // Ordered by priority

    public static func profile(for model: String) -> ATAProfile {
        for profile in profiles {
            if profile.matches(model) {
                return profile
            }
        }
        return genericProfile
    }

    public static func attributeInfo(id: UInt8, profile: ATAProfile) -> AttributeOverride {
        if let override = profile.attributes[id] {
            return override
        }
        if let generic = genericAttributes[id] {
            return generic
        }
        return AttributeOverride(name: L("Vendor-specific attribute", "Attribut propre au fabricant"), explanation: L("Attribute specific to this model. Its meaning isn't publicly documented.", "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement."), role: .none)
    }
}

public extension ATASmartAttribute {
    func value(for role: ATARole) -> UInt64? {
        switch role {
        case .temperature:
            let temp = raw[0]
            if temp >= 1 && temp <= 99 {
                return UInt64(temp)
            }
            return nil
        case .powerOnHours:
            var val: UInt64 = 0
            for i in 0..<4 {
                val |= (UInt64(raw[i]) << (i * 8))
            }
            return val
        case .hostWritesBytes(let multiplier), .hostReadsBytes(let multiplier):
            return rawValue.saturatingMultiplied(by: multiplier)
        case .lifeRemainingPercentNormalized:
            return UInt64(current)
        case .powerCycles, .unsafeShutdowns, .reallocated, .pending, .uncorrectable:
            return rawValue
        case .none:
            return nil
        }
    }
}
