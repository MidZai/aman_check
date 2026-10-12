import Foundation
import DiskHealthCore

/// Valeur brute d'une mesure (conservée telle quelle dans le JSON du rapport).
public enum MeasuredValue: Codable, Hashable, Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case bool(Bool)

    public var intValue: Int64? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int64(v.rounded())
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        default: return nil
        }
    }
}

/// Toute information collectée par l'app : décision d'architecture centrale (spec §4).
///
/// La valeur est typée par `MeasuredValue` plutôt que par un paramètre générique :
/// le rapport mélange des entiers, des textes et des durées dans une seule liste
/// et doit s'encoder en JSON tel quel.
public struct Measurement: Codable, Hashable, Sendable, Identifiable {
    /// Identifiant technique (`battery.health_percent`) : jamais affiché, voir `MetricCatalog`.
    public let id: String
    /// `nil` si la donnée n'a pas pu être lue.
    public let value: MeasuredValue?
    public let unit: String?
    public let status: CheckStatus
    public let provenance: Provenance
    /// Méthode de calcul ou source lue (« NominalChargeCapacity / DesignCapacity »), section Avancé.
    public let method: String?
    public let collectedAt: Date
    /// Valeur formatée pour l'affichage (« 115,2 To »), calculée une fois par le collecteur
    /// avec les formateurs d'Aman Disk : le rendu n'a aucune logique de formatage.
    public let display: String?
    /// Sous-texte humain (« ≈ 5 mois sous tension »).
    public let detail: String?
    /// Explication (« pourquoi non disponible », limite d'un contrôle…).
    public let note: String?

    public init(id: String,
                value: MeasuredValue?,
                unit: String? = nil,
                status: CheckStatus,
                provenance: Provenance = .measuredAuto,
                method: String? = nil,
                collectedAt: Date = Date(),
                display: String? = nil,
                detail: String? = nil,
                note: String? = nil) {
        self.id = id
        self.value = value
        self.unit = unit
        // Règle du projet : une donnée absente n'est jamais verte (ni orange, ni rouge, ni « info »).
        if value == nil, status.isJudgement || status == .info {
            self.status = .unavailable
        } else {
            self.status = status
        }
        self.provenance = provenance
        self.method = method
        self.collectedAt = collectedAt
        self.display = display
        self.detail = detail
        self.note = note
    }

    /// Libellé humain tiré du catalogue.
    public var label: String { MetricCatalog.info(for: id).label }

    /// Texte de la valeur, ou le libellé de statut quand il n'y a pas de valeur.
    public var displayText: String {
        if let display { return display }
        switch value {
        case .int(let v)?: return "\(v)\(unit.map { "\u{00A0}\($0)" } ?? "")"
        case .double(let v)?: return "\(v)\(unit.map { "\u{00A0}\($0)" } ?? "")"
        case .text(let s)?: return s
        case .bool(let b)?: return b ? L("Yes", "Oui") : L("No", "Non")
        case nil: return status.label
        }
    }
}

public extension Measurement {
    /// Mesure impossible à lire, avec son explication.
    static func unavailable(_ id: String, note: String, method: String? = nil) -> Measurement {
        Measurement(id: id, value: nil, status: .unavailable, method: method, note: note)
    }

    /// Contrôle que l'app ne peut pas faire : l'utilisateur doit le faire lui-même.
    static func manual(_ id: String, display: String? = nil, note: String) -> Measurement {
        Measurement(id: id, value: nil, status: .manualRequired, display: display, note: note)
    }
}
