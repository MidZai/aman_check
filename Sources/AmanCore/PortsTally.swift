import Foundation
import DiskHealthCore

/// Comptage des ports USB-C testés, isolé du matériel : seuls les connecteurs du Mac lui-même, identifiés
/// par leur numéro de port USB-C, remplissent une case ; un périphérique derrière un concentrateur n'a pas
/// de numéro et ne compte pas.
public enum PortsTally {
    public enum Verdict: Equatable {
        /// Tous les ports attendus ont été vus.
        case complete
        /// Une partie seulement, aucun port déclaré mort.
        case partial(seen: Int, total: Int)
        /// Un port déclaré mort.
        case failed
        /// Aucun port vu.
        case none
    }

    /// Numéros de port (1…total) effectivement vus, sans doublon, dans l'ordre.
    public static func filledSlots(portNumbers: [Int?], total: Int) -> [Int] {
        var seen: [Int] = []
        for case let n? in portNumbers where (1...max(total, 1)).contains(n) && !seen.contains(n) {
            seen.append(n)
        }
        return seen
    }

    public static func verdict(portNumbers: [Int?], total: Int, anyDead: Bool) -> Verdict {
        if anyDead { return .failed }
        let seen = filledSlots(portNumbers: portNumbers, total: total).count
        if seen == 0 { return .none }
        return seen >= total ? .complete : .partial(seen: seen, total: total)
    }

    public static func partialText(seen: Int, total: Int) -> String {
        L("\(seen) of \(total) ports tested.", "\(seen) ports testés sur \(total).")
    }

    public static var hubHint: String {
        L("Plug the device directly into the Mac, without a hub.", "Branchez l'appareil directement sur le Mac, sans concentrateur.")
    }
}
