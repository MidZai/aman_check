import Foundation
import DiskHealthCore

/// Ce que les tests audio enregistrent sur le périphérique utilisé : sa catégorie, jamais son nom
/// (« AirPods Pro de Karim » n'a rien à faire dans un rapport).
public enum AudioDeviceText {
    public static func category(isBuiltIn: Bool, input: Bool) -> String {
        switch (input, isBuiltIn) {
        case (true, true): return L("Built-in microphone", "Micro intégré")
        case (true, false): return L("External microphone", "Micro externe")
        case (false, true): return L("Built-in speakers", "Haut-parleurs intégrés")
        case (false, false): return L("External output", "Sortie externe")
        }
    }

    /// Un périphérique externe ne permet pas d'enregistrer le test comme réussi pour ce Mac.
    public static var externalDeviceReason: String {
        L("An external audio device was in use: disconnect it and run the test again.",
          "Un périphérique audio externe était utilisé : débranchez-le et relancez le test.")
    }
}
