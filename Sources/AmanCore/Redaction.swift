import Foundation

/// Masquage des identifiants matériels dans les sorties brutes (export de diagnostic).
/// Règle du projet : aucun numéro de série (Mac, batterie, SSD, écrans) ni UUID ne quitte l'app en clair.
public enum Redaction {
    public static let mask = "•••"

    /// Masque la valeur de toute clé dont le nom contient « serial », « uuid » ou « udid » :
    /// clés JSON (`serial_number`, `sppower_battery_serial_number`, `_spdisplays_display-serial-number`,
    /// `platform_UUID`…) et lignes de texte « Serial Number (system): … ».
    public static func identifiers(in text: String) -> String {
        let jsonKey = #"("[^"\n]*(?i:serial|uuid|udid)[^"\n]*"\s*:\s*")(?:[^"\\]|\\.)*""#
        let textLine = #"(?m)^([ \t]*[^:"\n]*(?i:serial|uuid|udid)[^:"\n]*:[ \t]*)\S.*$"#
        return text
            .replacingOccurrences(of: jsonKey, with: "$1\(mask)\"", options: .regularExpression)
            .replacingOccurrences(of: textLine, with: "$1\(mask)", options: .regularExpression)
    }
}
