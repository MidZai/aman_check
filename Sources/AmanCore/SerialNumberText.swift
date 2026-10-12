import Foundation
import DiskHealthCore

/// Ce que les 4 derniers caractères du numéro de série permettent, selon la génération du Mac.
public enum SerialNumberText {
    /// Sur les numéros de série à 12 caractères (Mac Intel, premiers M1), les 4 derniers caractères désignent
    /// la configuration du modèle, pas l'exemplaire : deux Mac identiques ont les mêmes. Rien à dire pour
    /// les numéros aléatoires récents (10 caractères).
    public static func configurationNote(serialLength: Int) -> String? {
        guard serialLength == 12 else { return nil }
        return L("On this generation of Mac, these 4 characters are shared by every Mac of the same configuration. They don't identify this exact Mac: compare the full serial number.",
                 "Sur cette génération de Mac, ces 4 caractères sont communs à tous les Mac de même configuration. Ils n'identifient pas cet exemplaire : comparez le numéro de série complet.")
    }
}
