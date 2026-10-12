import Foundation
import AmanCore

/// Seul point du code qui ouvre une connexion réseau (cahier des charges niveau 2, §8).
/// Aucune requête tant que l'utilisateur n'a pas confirmé la publication ; aucune télémétrie.
struct PublishClient: Sendable {
    /// Hôte unique autorisé. TODO (question ouverte §14) : nom de domaine définitif, identique à
    /// `PUBLIC_BASE_URL` du serveur. `.invalid` ne se résout jamais : rien ne part tant qu'il n'est pas choisi.
    static let productionBaseURL = URL(string: "https://aman-check.invalid")!

    /// En développement uniquement : `--publish-server http://127.0.0.1:8787` (serveur local, jamais un autre hôte).
    static var baseURL: URL {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--publish-server"), i + 1 < args.count,
           let url = URL(string: args[i + 1]), ["127.0.0.1", "localhost"].contains(url.host ?? "") {
            return url
        }
        return productionBaseURL
    }

    /// Vrai seulement si l'hôte n'est pas un domaine `.invalid` : tant que le domaine définitif n'est pas
    /// renseigné, la fonction de publication n'apparaît nulle part (le mode `--publish-server` local reste possible).
    static var isAvailable: Bool { PublicationAvailability.isAvailable(host: baseURL.host) }

    /// Domaine affiché à l'utilisateur, pour qu'il le reconnaisse sur le PDF et la page.
    static var displayHost: String { baseURL.host.map { $0 + (baseURL.port.map { ":\($0)" } ?? "") } ?? "" }

    static var purchaseURL: URL { baseURL.appendingPathComponent("acheter") }

    let baseURL: URL
    let appVersion: String
    private let session: URLSession

    init(baseURL: URL = PublishClient.baseURL, appVersion: String) {
        self.baseURL = baseURL
        self.appVersion = appVersion
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    struct PublishResponse: Decodable, Sendable {
        let publicId: String
        let url: String
        let sha256: String
        let publishedAt: Date
        let signature: String
        let keyId: String
        let validUntil: Date
        let creditsRemaining: Int?
        let manageToken: String

        var record: PublicationRecord {
            PublicationRecord(publicId: publicId, url: url, sha256: sha256, publishedAt: publishedAt, signature: signature,
                              keyId: keyId, validUntil: validUntil)
        }
    }

    struct LicenseInfo: Decodable, Sendable, Equatable {
        let plan: String
        let creditsRemaining: Int?
        let validUntil: Date?
        let active: Bool
        let publicationsThisMonth: Int?
        let monthlyCap: Int?
        let shopName: String?
        let logo: String?

        var isPro: Bool { plan == "pro" }
        var logoData: Data? { logo.flatMap { Data(base64Encoded: $0) } }
    }

    /// `POST /v1/reports` : les octets exacts du rapport. Une nouvelle tentative avec les mêmes octets
    /// renvoie la même publication, sans débit supplémentaire.
    func publish(reportBytes: Data, licenseKey: String) async throws -> PublishResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/reports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        request.httpBody = reportBytes
        return try await send(request)
    }

    /// `DELETE /v1/reports/{publicId}` avec le jeton de gestion.
    func withdraw(publicId: String, manageToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/reports/\(publicId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(manageToken)", forHTTPHeaderField: "Authorization")
        let _: [String: String] = try await send(request)
    }

    /// `GET /v1/licenses/me` : offre et solde.
    func license(key: String) async throws -> LicenseInfo {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/licenses/me"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PublishError.network
        }
        guard let http = response as? HTTPURLResponse else { throw PublishError.server }
        guard (200..<300).contains(http.statusCode) else {
            throw PublishError(code: (try? JSONDecoder().decode(APIFailure.self, from: data))?.error)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PublishError.server
        }
    }
}

/// Corps d'une réponse d'erreur de l'API : `{"error": "no_credit"}`.
private struct APIFailure: Decodable {
    let error: String?
}
