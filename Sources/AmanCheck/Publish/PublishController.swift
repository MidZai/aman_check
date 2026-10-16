import Foundation
import SwiftUI
import AppKit
import AmanCore
import DiskHealthCore

/// Publication d'un rapport vérifiable (niveau 2). La logique pure est dans AmanCore
/// (`PublicationRecord`, `PublishError`, `PublicationPayload`) ; ici, l'état de l'interface,
/// le trousseau et l'archive locale.
@MainActor
final class PublishController: ObservableObject {
    enum State: Equatable {
        case idle
        case publishing
        case failed(PublishError)
    }

    @Published private(set) var state: State = .idle
    /// Type d'information trouvé par le contrôle avant envoi (jamais la valeur), affiché sous l'erreur.
    @Published private(set) var privacyIssueText: String?
    @Published var licenseKey: String
    @Published private(set) var license: PublishClient.LicenseInfo?
    @Published private(set) var licenseError: PublishError?
    @Published private(set) var checkingLicense = false
    /// Publications faites depuis ce Mac (les plus récentes d'abord).
    @Published private(set) var entries: [PublicationEntry] = []
    /// Rapport exactement tel que publié, par identifiant de rapport : le PDF de niveau 2 reprend ce contenu.
    @Published private(set) var published: [String: PublishedReportArchive] = [:]
    @Published var showSheet = false
    @Published private(set) var withdrawing: String?

    private let client = PublishClient(appVersion: AppInfo.version)

    init() {
        // Fonction masquée (domaine non renseigné) : ni lecture du trousseau, ni fichier.
        guard PublishClient.isAvailable else {
            licenseKey = ""
            return
        }
        licenseKey = Keychain.read(Keychain.licenseAccount) ?? ""
        entries = Self.loadEntries()
    }

    // MARK: Niveau affiché

    func publication(for reportID: String) -> PublicationRecord? {
        published[reportID]?.publication
    }

    func level(for reportID: String) -> Int {
        TrustLevel.current(reportID: reportID, publications: published.mapValues(\.publication))
    }

    /// Le rapport à l'écran a changé depuis sa publication (nom du vendeur, tests refaits…).
    func hasChangesSincePublication(_ report: ConditionReport) -> Bool {
        guard let archive = published[report.reportID], let data = try? ReportCoding.encode(report) else { return false }
        return ReportCoding.sha256(data) != archive.publication.sha256
    }

    // MARK: Licence

    func checkLicense() async {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        checkingLicense = true
        defer { checkingLicense = false }
        do {
            license = try await client.license(key: key)
            licenseError = nil
            Keychain.write(key, account: Keychain.licenseAccount)
        } catch let error as PublishError {
            license = nil
            licenseError = error
        } catch {
            licenseError = .server
        }
    }

    func openPurchasePage() {
        NSWorkspace.shared.open(PublishClient.purchaseURL)
    }

    // MARK: Publication

    func publish(_ report: ConditionReport) async {
        guard state != .publishing else { return }
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { state = .failed(.invalidLicense); return }
        guard !report.simulated else { state = .failed(.simulatedProfile); return }

        let bytes: Data
        do {
            bytes = try ReportCoding.encode(report)
        } catch {
            state = .failed(.invalidReport)
            return
        }
        // Contrôle avant envoi : rien de la colonne « Jamais envoyé » (§10).
        let secrets: [PublicationSecret] = [
            SystemReader.serialNumber.map { PublicationSecret(.serialNumber, $0) },
            Host.current().localizedName.map { PublicationSecret(.computerName, $0) },
            PublicationSecret(.computerName, ProcessInfo.processInfo.hostName),
            PublicationSecret(.userName, NSUserName()),
            PublicationSecret(.fullName, NSFullUserName())
        ].compactMap { $0 }
        let issues = PublicationPayload.issues(in: bytes, secrets: secrets, allowed: [report.profile.displayName, report.profile.modelIdentifier])
        guard issues.isEmpty else {
            DiagnosticLog.shared.log("publication", "contrôle avant envoi : \(issues.count) problème(s)")
            // Le type d'information trouvé est montré à l'utilisateur, jamais la valeur.
            privacyIssueText = PublicationPayload.describe(issues: issues)
            state = .failed(.privacyCheckFailed)
            return
        }

        state = .publishing
        DiagnosticLog.shared.log("publication", "envoi de \(bytes.count) octets")
        do {
            let response = try await client.publish(reportBytes: bytes, licenseKey: key)
            // L'empreinte renvoyée doit être celle des octets envoyés.
            guard response.sha256 == ReportCoding.sha256(bytes) else { throw PublishError.server }
            Keychain.write(key, account: Keychain.licenseAccount)
            Keychain.write(response.manageToken, account: Keychain.manageTokenAccount(response.publicId))
            let archive = PublishedReportArchive(report: report, publication: response.record)
            published[report.reportID] = archive
            Self.saveArchive(archive)
            entries.removeAll { $0.id == response.publicId }
            entries.insert(PublicationEntry(reportID: report.reportID, modelName: report.profile.displayName,
                                            generatedAt: report.generatedAt, record: response.record), at: 0)
            Self.saveEntries(entries)
            if let credits = response.creditsRemaining, let current = license {
                license = PublishClient.LicenseInfo(plan: current.plan, creditsRemaining: credits, validUntil: current.validUntil,
                                                    active: credits > 0, publicationsThisMonth: current.publicationsThisMonth,
                                                    monthlyCap: current.monthlyCap, shopName: current.shopName, logo: current.logo)
            }
            DiagnosticLog.shared.log("publication", "publié : \(response.publicId)")
            state = .idle
            showSheet = false
        } catch let error as PublishError {
            DiagnosticLog.shared.log("publication", "échec : \(error.rawValue)")
            state = .failed(error)
        } catch {
            state = .failed(.server)
        }
    }

    func resetError() {
        if case .failed = state { state = .idle }
    }

    // MARK: Retrait

    func withdraw(_ entry: PublicationEntry) async {
        guard let token = Keychain.read(Keychain.manageTokenAccount(entry.id)) else {
            state = .failed(.invalidToken)
            return
        }
        withdrawing = entry.id
        defer { withdrawing = nil }
        do {
            try await client.withdraw(publicId: entry.id, manageToken: token)
        } catch PublishError.notFound {
            // Déjà absent du serveur : on le considère retiré.
        } catch let error as PublishError {
            state = .failed(error)
            return
        } catch {
            state = .failed(.server)
            return
        }
        Keychain.delete(Keychain.manageTokenAccount(entry.id))
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index].withdrawn = true }
        Self.saveEntries(entries)
        if published[entry.reportID]?.publication.publicId == entry.id { published[entry.reportID] = nil }
        DiagnosticLog.shared.log("publication", "retiré : \(entry.id)")
    }

    // MARK: Textes

    func listingText(for record: PublicationRecord, report: ConditionReport) -> String {
        Level2Text.listingText(date: Formatters.longDate(report.generatedAt), url: record.url)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Archive locale (Application Support)

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Aman Check/Publications", isDirectory: true)
    }

    private static var indexURL: URL { directory.appendingPathComponent("publications.json") }

    private static func loadEntries() -> [PublicationEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? ReportCoding.decoder().decode([PublicationEntry].self, from: data)) ?? []
    }

    private static func saveEntries(_ entries: [PublicationEntry]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? ReportCoding.encoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    private static func saveArchive(_ archive: PublishedReportArchive) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(archive.publication.publicId).json")
        try? ReportCoding.encoder().encode(archive).write(to: url, options: .atomic)
    }
}

extension PublishController {
    /// Export PDF unique pour le menu Contrôle, la barre d'outils et l'écran Rapport : si le rapport a été publié,
    /// le PDF porte le QR code et le lien de vérification (archive) et, en Pro, le logo de la boutique.
    func shareablePDF(_ report: ConditionReport, detailed: Bool = true) -> URL? {
        ReportExporter.shareablePDF(report, detailed: detailed, archive: published[report.reportID],
                                    logo: license?.isPro == true ? license?.logoData : nil)
    }

    func exportPDF(_ report: ConditionReport, detailed: Bool = true) {
        ReportExporter.exportPDF(report, detailed: detailed, archive: published[report.reportID],
                                 logo: license?.isPro == true ? license?.logoData : nil)
    }
}
