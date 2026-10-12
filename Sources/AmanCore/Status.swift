import Foundation
import DiskHealthCore

/// Verdict d'une mesure ou d'un test.
/// Seuls `good`, `watch` et `problem` sont des jugements : ce sont les seuls qui reçoivent
/// une couleur verte, orange ou rouge. Une donnée sans jugement (modèle, RAM…) est `info`.
public enum CheckStatus: String, Codable, Sendable, CaseIterable {
    case good              // Bon
    case watch             // À surveiller
    case problem           // Problème détecté
    case notTested         // Non testé
    case unavailable       // Non disponible (donnée inaccessible sur cette machine)
    case manualRequired    // Vérification manuelle requise
    case notApplicable     // Sans objet (ex. batterie sur iMac)
    case info              // Information, sans jugement (modèle, processeur…)

    /// Vert, orange ou rouge : uniquement quand l'app a réellement évalué quelque chose.
    public var isJudgement: Bool {
        switch self {
        case .good, .watch, .problem: return true
        default: return false
        }
    }

    /// Ce que l'acheteur doit encore vérifier lui-même.
    public var needsFollowUp: Bool {
        switch self {
        case .watch, .problem, .notTested, .unavailable, .manualRequired: return true
        default: return false
        }
    }

    /// Ordre de gravité pour trier les listes (le plus grave d'abord).
    public var severity: Int {
        switch self {
        case .problem: return 0
        case .watch: return 1
        case .manualRequired: return 2
        case .unavailable: return 3
        case .notTested: return 4
        case .good: return 5
        case .info: return 6
        case .notApplicable: return 7
        }
    }

    public var label: String {
        switch self {
        case .good: return L("Good", "Bon")
        case .watch: return L("Needs attention", "À surveiller")
        case .problem: return L("Problem detected", "Problème détecté")
        case .notTested: return L("Not tested", "Non testé")
        case .unavailable: return L("Not available", "Non disponible")
        case .manualRequired: return L("Check manually", "Vérification manuelle")
        case .notApplicable: return L("Not applicable", "Sans objet")
        case .info: return L("Information", "Information")
        }
    }

    /// Mêmes symboles qu'Aman Disk pour les trois jugements (HealthStatus+Color.swift).
    public var symbolName: String {
        switch self {
        case .good: return "checkmark.circle"
        case .watch: return "exclamationmark.triangle"
        case .problem: return "xmark.octagon"
        case .notTested: return "circle.dashed"
        case .unavailable: return "questionmark.circle"
        case .manualRequired: return "hand.raised"
        case .notApplicable: return "minus.circle"
        case .info: return "info.circle"
        }
    }
}

/// D'où vient une valeur. Affiché dans le rapport à côté de chaque résultat.
public enum Provenance: String, Codable, Sendable {
    case measuredAuto      // lu par l'app depuis le système
    case userObserved      // constaté et déclaré par l'utilisateur
    case derived           // calculé à partir d'autres mesures

    public var label: String {
        switch self {
        case .measuredAuto: return L("Measured automatically", "Mesuré automatiquement")
        case .userObserved: return L("Observed by the user", "Constaté par l'utilisateur")
        case .derived: return L("Calculated", "Calculé")
        }
    }

    public var shortLabel: String {
        switch self {
        case .measuredAuto: return L("measured", "mesuré")
        case .userObserved: return L("observed", "constaté")
        case .derived: return L("calculated", "calculé")
        }
    }
}
