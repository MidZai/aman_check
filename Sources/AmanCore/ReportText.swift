import Foundation
import DiskHealthCore

/// Textes fixes du rapport (spec §3). Le bandeau de bas de rapport est obligatoire.
public enum ReportText {
    public static var title: String { L("Condition report", "Rapport d'état") }

    public static var disclaimer: String {
        L("This report is a snapshot taken on the date shown. Values marked Measured automatically come from the tested Mac's system; values marked Observed by the user are declarative. This document is neither a certification nor a warranty.",
          "Ce rapport est un instantané établi à la date indiquée. Les valeurs marquées Mesuré automatiquement proviennent du système du Mac testé ; les valeurs marquées Constaté par l'utilisateur sont déclaratives. Ce document ne constitue ni une certification ni une garantie.")
    }

    public static var trustLevel1: String { L("Level 1 · Local condition report", "Niveau 1 · Rapport d'état local") }

    public static var trustExplanation: String {
        L("Level 1: automatic snapshot plus tests declared by the person, generated on this Mac. No certification.\nLevel 2 (optional, paid): the same report registered online, viewable with a link or a QR code; the page shows that it has not been changed since.\nLevel 3 (later): check carried out by a partner repairer who takes responsibility for it.",
          "Niveau 1 : instantané automatique et tests déclarés par la personne, générés sur ce Mac. Aucune certification.\nNiveau 2 (facultatif, payant) : le même rapport enregistré en ligne, consultable par lien ou QR code ; la page montre qu'il n'a pas été modifié depuis.\nNiveau 3 (plus tard) : contrôle réalisé par un réparateur partenaire qui en engage la responsabilité.")
    }

    /// Rapport produit avec `--simulate-model` (développement) : affiché en tête du PDF.
    public static var simulatedWarning: String {
        L("Simulated profile (development): the model and its capabilities come from the catalog, the measurements from another Mac. This report does not describe a real Mac.",
          "Profil simulé (développement) : le modèle et ses capacités viennent du catalogue, les mesures d'un autre Mac. Ce rapport ne décrit pas un vrai Mac.")
    }
}
