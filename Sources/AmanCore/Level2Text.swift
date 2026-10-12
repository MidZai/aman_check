import Foundation
import DiskHealthCore

/// Textes du niveau 2 (rapport vérifiable en ligne), partagés par l'app et la page publique :
/// la page les reçoit par l'export JSON du catalogue (`AmanCatalogExport`), jamais recopiés à la main.
/// Lexique (règle 2) : « rapport vérifiable », « rapport enregistré » ; jamais « certifié » ni « authentifié ».
public enum Level2Text {
    public static var trustLevel2: String { L("Level 2 · Report registered online", "Niveau 2 · Rapport enregistré en ligne") }

    public static var verifiableReport: String { L("Verifiable report", "Rapport vérifiable") }

    /// Variante niveau 2 du bandeau légal. TODO: à faire relire avant la mise en ligne (§14).
    public static var disclaimer: String {
        L("This report is a snapshot taken on the date shown and registered online by Aman Check. The registration shows that its content has not been changed since it was published; it says nothing about the Mac's condition today. Values marked Measured automatically come from the tested Mac's system; values marked Observed by the user are declarative. It makes no promise about how the Mac works or how long it will last.",
          "Ce rapport est un instantané établi à la date indiquée et enregistré en ligne par Aman Check. L'enregistrement montre que son contenu n'a pas été modifié depuis sa publication ; il ne dit rien de l'état du Mac aujourd'hui. Les valeurs marquées Mesuré automatiquement proviennent du système du Mac testé ; les valeurs marquées Constaté par l'utilisateur sont déclaratives. Il n'engage aucune promesse sur le fonctionnement du Mac ni sur sa durée de vie.")
    }

    // MARK: Ce que la page prouve et ne prouve pas (§1, §11)

    public static var provesTitle: String { L("What this report proves and does not prove", "Ce que ce rapport prouve et ne prouve pas") }

    public static var proves: [String] {
        [L("It was produced by the Aman Check app, on the date shown.", "Il a été produit par l'app Aman Check, à la date indiquée."),
         L("Its content has not been changed since it was published.", "Son contenu n'a pas été modifié depuis sa publication."),
         L("It concerns a Mac whose serial number ends with the 4 characters shown.", "Il concerne un Mac dont le numéro de série se termine par les 4 caractères affichés.")]
    }

    public static var doesNotProve: [String] {
        [L("That the Mac is in good condition today: the report dates from the day of the check.", "Que le Mac est en bon état aujourd'hui : le rapport date du jour du contrôle."),
         L("That the tests marked Observed by the user are accurate: they are declarative.", "Que les tests « Constaté par l'utilisateur » sont exacts : ils sont déclaratifs."),
         L("That the Mac is neither stolen nor locked after it is erased.", "Que le Mac n'est ni volé ni verrouillé après effacement."),
         L("That the seller did not produce a misleading report on their own Mac: the registration prevents changes after the fact, not a determined seller.",
           "Que le vendeur n'a pas fabriqué un rapport trompeur sur son propre Mac : l'enregistrement empêche les retouches après coup, pas un vendeur déterminé.")]
    }

    // MARK: Vérifications de l'acheteur (§3, §7)

    public static var checkThisMacTitle: String { L("Check that it is this Mac", "Vérifiez que c'est bien ce Mac") }

    public static var checkThisMac: String {
        L("Compare the last 4 characters with the serial number engraved under the Mac, or shown in Apple menu › About This Mac. This only helps rule out an obvious mix-up: on some generations, every Mac of the same configuration shares them.",
          "Comparez les 4 derniers caractères avec le numéro de série gravé sous la machine, ou affiché dans le menu Pomme › À propos de ce Mac. Cela permet seulement d'écarter une erreur grossière : sur certaines générations, tous les Mac de même configuration les partagent.")
    }

    public static var buyerChecks: [String] {
        [L("Compare the 4 characters of the serial number with the ones on the Mac: enough to rule out an obvious mix-up, not to tell two identical Macs apart.",
           "Comparez les 4 caractères du numéro de série avec ceux du Mac : cela suffit à écarter une erreur grossière, pas à distinguer deux Mac identiques."),
         L("Compare the date of the report with the date of the listing.", "Comparez la date du rapport avec celle de l'annonce."),
         L("Ask for the Mac to be erased in front of you, and check that setup asks for no Apple Account or company sign-in.",
           "Faites effacer le Mac devant vous, et vérifiez que l'assistant de configuration ne demande aucun identifiant Apple ni d'entreprise.")]
    }

    public static var pdfMatch: String {
        L("If you were given a PDF, check that its identifier and date match this page. The content of this page is the one that counts.",
          "Si l'on vous a remis un PDF, vérifiez que son identifiant et sa date correspondent à cette page. Le contenu qui fait foi est celui de cette page.")
    }

    // MARK: États du rapport publié (§5). « {date} » et « {url} » sont remplacés à l'affichage.

    public static func stateValid(date: String) -> String {
        L("Report registered on \(date), content unchanged since.", "Rapport enregistré le \(date), contenu non modifié depuis.")
    }

    public static var stateOld: String {
        L("This report is more than 30 days old. Ask for a new check.", "Ce rapport date de plus de 30 jours. Demandez un nouveau contrôle.")
    }

    public static var stateReplaced: String {
        L("A more recent report exists for this Mac.", "Un rapport plus récent existe pour ce Mac.")
    }

    public static var stateReplacedLink: String { L("See the latest version", "Voir la version récente") }

    public static var stateWithdrawn: String { L("This report was withdrawn by its author.", "Ce rapport a été retiré par son auteur.") }

    public static var stateNotFound: String {
        L("No report matches this link. Be wary of a PDF whose QR code leads here.",
          "Aucun rapport ne correspond à ce lien. Méfiez-vous d'un PDF dont le QR code mène ici.")
    }

    public static var stateErased: String {
        L("The content of this report was erased 90 days after it was published. Only its identifier, fingerprint and dates remain.",
          "Le contenu de ce rapport a été effacé 90 jours après sa publication. Il ne reste que son identifiant, son empreinte et ses dates.")
    }

    // MARK: Publication depuis l'app (§3, §8, §10)

    /// Texte prêt à coller dans une annonce.
    public static func listingText(date: String, url: String) -> String {
        L("Aman Check condition report of \(date), available here: \(url)",
          "Rapport d'état Aman Check du \(date), consultable ici : \(url)")
    }

    public static func publishedAsIs(untested: Int, blockers: Int) -> String? {
        var parts: [String] = []
        if untested > 0 {
            parts.append(untested == 1 ? L("1 test not done", "1 test non réalisé")
                                       : L("\(untested) tests not done", "\(untested) tests non réalisés"))
        }
        if blockers > 0 {
            parts.append(blockers == 1 ? L("1 blocking issue", "1 point bloquant")
                                       : L("\(blockers) blocking issues", "\(blockers) points bloquants"))
        }
        guard !parts.isEmpty else { return nil }
        let list = parts.joined(separator: L(" and ", " et "))
        return L("Your report will be published as is, with \(list).", "Votre rapport sera publié tel quel, avec \(list).")
    }

    public static var sentTitle: String { L("Sent and made public", "Envoyé et rendu public") }
    public static var neverSentTitle: String { L("Never sent", "Jamais envoyé") }

    /// Les deux listes de la feuille de confirmation, mot pour mot (§10).
    public static var sent: [String] {
        [L("Model, year, processor, memory, storage, macOS version", "Modèle, année, processeur, mémoire, stockage, version de macOS"),
         L("Last 4 characters of the serial number", "4 derniers caractères du numéro de série"),
         L("Battery, SSD, lock and wireless measurements", "Mesures de batterie, de SSD, de verrouillages, de sans-fil"),
         L("Results of the guided tests and their date", "Résultats des tests guidés et leur date"),
         L("Name of the seller or shop, if entered", "Nom du vendeur ou du magasin, s'il a été saisi"),
         L("Version of the app and of the procedure", "Version de l'app et de la procédure")]
    }

    public static var neverSent: [String] {
        [L("The Mac's full serial number", "Numéro de série complet du Mac"),
         L("Serial numbers of the battery, SSD and displays", "Numéros de série de la batterie, du SSD, des écrans"),
         L("Account name, computer name, Apple Account", "Nom du compte, nom de l'ordinateur, identifiant Apple"),
         L("Files, photos, audio or video recordings from the tests", "Fichiers, photos, enregistrements audio ou vidéo des tests"),
         L("Wi-Fi network names, Bluetooth devices", "Noms des réseaux Wi-Fi, appareils Bluetooth"),
         L("Diagnostic log and raw command output", "Journal de diagnostic et sorties brutes des commandes")]
    }

    public static var sellerNameReminder: String {
        L("This name will be visible to anyone who has the link.", "Ce nom sera visible par toute personne ayant le lien.")
    }

    public static var nothingSentWithoutConsent: String {
        L("Nothing is sent without your consent.", "Rien n'est envoyé sans votre accord.")
    }

    public static var footerCTA: String {
        L("Check your Mac for free with Aman Check", "Contrôlez votre Mac gratuitement avec Aman Check")
    }

    /// Aperçu de lien (Open Graph) : aucun verdict.
    public static func linkPreview(model: String, date: String) -> String {
        L("Condition report · \(model) · checked on \(date)", "Rapport d'état · \(model) · contrôlé le \(date)")
    }

    /// Tous les textes du niveau 2, pour le test du lexique.
    public static var all: [String] {
        [trustLevel2, verifiableReport, disclaimer, provesTitle, checkThisMacTitle, checkThisMac, pdfMatch,
         stateValid(date: "{date}"), stateOld, stateReplaced, stateReplacedLink, stateWithdrawn, stateNotFound, stateErased,
         listingText(date: "{date}", url: "{url}"), publishedAsIs(untested: 3, blockers: 1) ?? "", sentTitle, neverSentTitle,
         sellerNameReminder, nothingSentWithoutConsent, footerCTA, linkPreview(model: "{model}", date: "{date}")]
            + proves + doesNotProve + buyerChecks + sent + neverSent + PublishError.allCases.map(\.message)
    }
}
