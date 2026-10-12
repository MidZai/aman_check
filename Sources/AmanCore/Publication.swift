import Foundation
import CryptoKit
import DiskHealthCore

/// Encodage du rapport : clés triées, dates ISO 8601, comme l'export JSON de niveau 1.
/// Les octets publiés sont exactement ceux-ci ; le serveur en calcule l'empreinte.
public enum ReportCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ report: ConditionReport) throws -> Data {
        try encoder().encode(report)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Bloc `publication` renvoyé par l'API (cahier des charges §5, §8).
public struct PublicationRecord: Codable, Sendable, Equatable {
    public let publicId: String
    public let url: String
    public let sha256: String
    public let publishedAt: Date
    public let signature: String
    public let keyId: String
    public let validUntil: Date

    public init(publicId: String, url: String, sha256: String, publishedAt: Date, signature: String, keyId: String, validUntil: Date) {
        self.publicId = publicId
        self.url = url
        self.sha256 = sha256
        self.publishedAt = publishedAt
        self.signature = signature
        self.keyId = keyId
        self.validUntil = validUntil
    }

    /// 8 premiers caractères de l'empreinte, imprimés en pied de page du PDF.
    public var shortFingerprint: String { String(sha256.prefix(8)) }
}

/// Archive JSON : le rapport, inchangé, et à côté le bloc de publication.
public struct PublishedReportArchive: Codable, Sendable {
    public let report: ConditionReport
    public let publication: PublicationRecord

    public init(report: ConditionReport, publication: PublicationRecord) {
        self.report = report
        self.publication = publication
    }

    /// Le rapport relu de l'archive se ré-encode octet pour octet en ce qui a été publié.
    public var matchesFingerprint: Bool {
        guard let data = try? ReportCoding.encode(report) else { return false }
        return ReportCoding.sha256(data) == publication.sha256
    }
}

/// Niveau de confiance affiché : dérivé, jamais stocké dans le rapport (§8).
public enum TrustLevel {
    /// 2 si une publication existe pour le rapport courant, 1 sinon (relancer le contrôle crée un nouveau rapport).
    public static func current(reportID: String, publications: [String: PublicationRecord]) -> Int {
        publications[reportID] != nil ? 2 : 1
    }
}

/// Une publication connue de l'app, conservée sur ce Mac pour pouvoir la retirer plus tard.
/// Le jeton de gestion, lui, est dans le trousseau.
public struct PublicationEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { record.publicId }
    public let reportID: String
    public let modelName: String
    public let generatedAt: Date
    public let record: PublicationRecord
    public var withdrawn: Bool

    public init(reportID: String, modelName: String, generatedAt: Date, record: PublicationRecord, withdrawn: Bool = false) {
        self.reportID = reportID
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.record = record
        self.withdrawn = withdrawn
    }
}

/// Erreurs de publication : une par code de l'API (§6), avec un message bilingue sans identifiant technique.
public enum PublishError: String, Error, CaseIterable, Sendable {
    case invalidReport = "invalid_report"
    case invalidLicense = "invalid_license"
    case noCredit = "no_credit"
    case tooLarge = "too_large"
    case reportTooOld = "report_too_old"
    case simulatedProfile = "simulated_profile"
    case appTooOld = "app_too_old"
    case rateLimited = "rate_limited"
    case notFound = "not_found"
    case invalidToken = "invalid_token"
    /// Pas de réponse du serveur (coupure, délai dépassé) : le rapport local reste intact.
    case network = "network"
    /// Réponse inattendue.
    case server = "server"
    /// Contrôle local avant envoi : le rapport contient une donnée qui ne doit pas quitter le Mac.
    case privacyCheckFailed = "privacy_check_failed"

    public init(code: String?) {
        self = code.flatMap(PublishError.init(rawValue:)) ?? .server
    }

    /// Message dans la langue de l'app.
    public var message: String { L(texts.en, texts.fr) }

    /// Message en anglais et en français.
    public var texts: (en: String, fr: String) {
        switch self {
        case .invalidReport: return ("The report could not be read. Run the check again.", "Le rapport n'a pas pu être lu. Relancez le contrôle.")
        case .invalidLicense: return ("This key is not recognized.", "Cette clé n'est pas reconnue.")
        case .noCredit: return ("There are no publications left on this key.", "Il ne reste plus de publication sur cette clé.")
        case .tooLarge: return ("Report too large.", "Rapport trop volumineux.")
        case .reportTooOld: return ("This check is more than 24 hours old. Run it again before publishing.", "Ce contrôle date de plus de 24 heures. Relancez-le avant de publier.")
        case .simulatedProfile: return ("A simulated profile cannot be published.", "Un profil simulé ne peut pas être publié.")
        case .appTooOld: return ("Update Aman Check to publish.", "Mettez à jour Aman Check pour publier.")
        case .rateLimited: return ("Too many attempts. Try again in a few minutes.", "Trop de tentatives. Réessayez dans quelques minutes.")
        case .notFound: return ("This report is no longer online.", "Ce rapport n'est plus en ligne.")
        case .invalidToken: return ("This Mac cannot withdraw this report.", "Ce Mac ne peut pas retirer ce rapport.")
        case .network: return ("The server could not be reached. Your report is still here and can be exported as a PDF; you can try again without being charged twice.",
                                "Le serveur n'a pas pu être joint. Votre rapport reste sur ce Mac et peut être exporté en PDF ; vous pouvez réessayer sans être débité deux fois.")
        case .server: return ("The server gave an unexpected answer. Try again later.", "Le serveur a répondu de façon inattendue. Réessayez plus tard.")
        case .privacyCheckFailed: return ("The report contains information that must not leave this Mac. Nothing was sent.",
                                           "Le rapport contient une information qui ne doit pas quitter ce Mac. Rien n'a été envoyé.")
        }
    }

    /// Erreur qui appelle un bouton d'achat.
    public var offersPurchase: Bool { self == .noCredit }
}

/// Contrôle avant envoi (§10) : le JSON ne contient aucun élément de la colonne « Jamais envoyé ».
public enum PublicationPayload {
    /// Mêmes clés interdites que le serveur (`server/src/validate.ts`).
    static let forbiddenKey = try! NSRegularExpression(
        pattern: "serial|uuid|udid|hostname|host_name|computer_?name|user_?name|apple_?id|ssid|bssid|raw|events|stdout|stderr",
        options: [.caseInsensitive])

    /// Problèmes trouvés (vide : envoi possible). `secrets` : numéro de série complet, nom de l'ordinateur,
    /// nom du compte… lus sur le Mac au moment de l'envoi, qui ne doivent apparaître nulle part.
    /// `allowed` : textes légitimes du rapport (nom du modèle…) ; un secret qu'ils contiennent déjà est ignoré
    /// (un ordinateur nommé « MacBook Pro » ne bloque pas la publication d'un rapport de MacBook Pro).
    public static func issues(in data: Data, secrets: [String], allowed: [String] = []) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return ["json"] }
        var issues: [String] = []
        func walk(_ node: Any, _ path: String) {
            if let dict = node as? [String: Any] {
                for (key, value) in dict {
                    let range = NSRange(key.startIndex..., in: key)
                    if forbiddenKey.firstMatch(in: key, range: range) != nil { issues.append("\(path).\(key)") }
                    walk(value, "\(path).\(key)")
                }
            } else if let array = node as? [Any] {
                for (i, value) in array.enumerated() { walk(value, "\(path)[\(i)]") }
            }
        }
        walk(root, "$")
        if let dict = root as? [String: Any], dict["simulated"] as? Bool == true { issues.append("$.simulated") }

        let text = String(decoding: data, as: UTF8.self).lowercased()
        for secret in secrets {
            let s = secret.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Les secrets trop courts (« Mac ») produiraient des faux positifs.
            guard s.count >= 5, !allowed.contains(where: { $0.lowercased().contains(s) }) else { continue }
            if text.contains(s) { issues.append("secret") }
        }
        return issues
    }
}
