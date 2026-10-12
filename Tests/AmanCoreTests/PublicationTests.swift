import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

/// Niveau 2 : tests unitaires AmanCore du cahier des charges (§12).
@Suite("Niveau 2 · publication")
struct PublicationTests {
    private func report(simulated: Bool = false, seller: String? = "Boutique Exemple") -> ConditionReport {
        let profile = simulated
            ? DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
            : DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        return ConditionReport(generatedAt: Date(timeIntervalSince1970: 1_791_712_800), appVersion: "1.0.0", profile: profile, measurements: [
            Measurement(id: MetricID.serial, value: .text("Q2XD"), status: .info, display: "••••Q2XD"),
            Measurement(id: MetricID.batteryHealth, value: .double(82.7), unit: "%", status: .good, display: "83 %"),
            Measurement(id: MetricID.storageDataWritten, value: .int(42_000_000_000_000), status: .info, display: "42 To"),
            SecurityAnalysis.firmwarePassword(chip: .intelT2)
        ], tests: [
            TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "66/66",
                       completedAt: Date(timeIntervalSince1970: 1_791_713_000.25))
        ], plannedTests: [.keyboard, .screen], sellerName: seller)
    }

    private func record(for data: Data) -> PublicationRecord {
        PublicationRecord(publicId: "7K3P-Q2XD-M4RT", url: "https://exemple.invalid/r/7K3P-Q2XD-M4RT", sha256: ReportCoding.sha256(data),
                          publishedAt: Date(timeIntervalSince1970: 1_791_720_000), signature: "c2ln", keyId: "k1",
                          validUntil: Date(timeIntervalSince1970: 1_794_312_000))
    }

    @Test("L'archive fait l'aller-retour JSON sans modifier un seul octet du rapport")
    func archiveRoundTrip() throws {
        let original = report()
        let published = try ReportCoding.encode(original)
        let archive = PublishedReportArchive(report: original, publication: record(for: published))

        let file = try ReportCoding.encoder().encode(archive)
        let back = try ReportCoding.decoder().decode(PublishedReportArchive.self, from: file)
        #expect(try ReportCoding.encode(back.report) == published)
        #expect(back.matchesFingerprint)
        #expect(back.publication == archive.publication)
        // Le rapport est inchangé : ni niveau, ni bloc de publication à l'intérieur.
        #expect(back.report.trustLevel == 1)
        #expect(!String(decoding: published, as: UTF8.self).contains("publicId"))
    }

    @Test("Niveau affiché : 2 avec une publication pour le rapport courant, 1 sinon, 1 après un nouveau contrôle")
    func derivedLevel() throws {
        let current = report()
        let publications = [current.reportID: record(for: try ReportCoding.encode(current))]
        #expect(TrustLevel.current(reportID: current.reportID, publications: publications) == 2)
        #expect(TrustLevel.current(reportID: current.reportID, publications: [:]) == 1)
        // Relancer le contrôle tire un nouvel identifiant de rapport.
        let rerun = ConditionReport(appVersion: "1.0.0", profile: current.profile, measurements: current.measurements,
                                    tests: [], plannedTests: current.plannedTests)
        #expect(rerun.reportID != current.reportID)
        #expect(TrustLevel.current(reportID: rerun.reportID, publications: publications) == 1)
    }

    @Test("Le JSON prêt à l'envoi ne contient aucun champ interdit")
    func payloadHasNoForbiddenField() throws {
        let data = try ReportCoding.encode(report())
        let secrets = [PublicationSecret(.serialNumber, "C02ZK1ABQ2XD"), PublicationSecret(.computerName, "MacBook-Pro-de-Karim.local"),
                       PublicationSecret(.userName, "karim"), PublicationSecret(.fullName, "Karim Benali")]
        #expect(PublicationPayload.issues(in: data, secrets: secrets).isEmpty)

        // Le champ « Vendeur ou boutique » est une saisie volontaire : le nom complet y est autorisé.
        var leaked = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        leaked["sellerName"] = "Karim Benali"
        #expect(PublicationPayload.issues(in: try JSONSerialization.data(withJSONObject: leaked), secrets: secrets).isEmpty)
        leaked = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        leaked["raw"] = ["SPPowerDataType": "…"]
        #expect(PublicationPayload.issues(in: try JSONSerialization.data(withJSONObject: leaked), secrets: []).contains("$.raw"))
        // Numéro de série complet dans une valeur de mesure : refusé, avec le type d'information trouvé.
        let withSerial = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"Q2XD\"", with: "\"C02ZK1ABQ2XD\"")
        #expect(PublicationPayload.issues(in: Data(withSerial.utf8), secrets: secrets) == ["secret:serialNumber"])
        let withKey = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"sellerName\"", with: "\"serial_number\" : \"x\", \"sellerName\"")
        #expect(PublicationPayload.issues(in: Data(withKey.utf8), secrets: []).contains("$.serial_number"))

        // Un ordinateur nommé comme le modèle ne bloque pas la publication.
        #expect(PublicationPayload.issues(in: data, secrets: [PublicationSecret(.computerName, "MacBook Pro")], allowed: [report().profile.displayName]).isEmpty)
    }

    @Test("Contrôle avant envoi : mots entiers, valeurs de la machine seulement, pas les textes fixes")
    func privacyCheckHasNoFalsePositives() throws {
        // « admin » et « apple » apparaissent dans les textes fixes (méthodes, libellés) : pas de blocage.
        let data = try ReportCoding.encode(report())
        #expect(PublicationPayload.issues(in: data, secrets: [PublicationSecret(.userName, "admin"), PublicationSecret(.userName, "apple")]).isEmpty)
        // Le nom d'utilisateur en mot entier dans une note de mesure : bloqué.
        let withNote = ConditionReport(appVersion: "1.0.0", profile: report().profile, measurements: [
            Measurement(id: MetricID.batteryHealth, value: .int(83), status: .good, note: "Checked by admin on this Mac")
        ], tests: [], plannedTests: [])
        #expect(PublicationPayload.issues(in: try ReportCoding.encode(withNote), secrets: [PublicationSecret(.userName, "admin")]) == ["secret:userName"])
        // Sous-chaîne d'un autre mot (« administrator ») : pas un mot entier, pas de blocage.
        let substring = ConditionReport(appVersion: "1.0.0", profile: report().profile, measurements: [
            Measurement(id: MetricID.batteryHealth, value: .int(83), status: .good, note: "administrator check")
        ], tests: [], plannedTests: [])
        #expect(PublicationPayload.issues(in: try ReportCoding.encode(substring), secrets: [PublicationSecret(.userName, "admin")]).isEmpty)
        // Message pour l'utilisateur : le type, jamais la valeur.
        let text = PublicationPayload.describe(issues: ["secret:serialNumber", "secret:computerName"])
        #expect(text == L("Found: serial number, computer name.", "Trouvé : numéro de série, nom de l'ordinateur."))
        #expect(PublicationPayload.describe(issues: ["$.raw"]) == nil)
    }

    @Test("Chaque code d'erreur de l'API a un message bilingue, sans identifiant technique")
    func errorMessages() {
        let apiCodes = ["invalid_report", "invalid_license", "no_credit", "too_large", "report_too_old", "simulated_profile",
                        "app_too_old", "rate_limited"]
        for code in apiCodes {
            let error = PublishError(code: code)
            #expect(error.rawValue == code, "\(code) sans valeur dédiée")
        }
        #expect(PublishError(code: "inconnu") == .server)
        #expect(PublishError(code: nil) == .server)
        for error in PublishError.allCases {
            let (en, fr) = error.texts
            #expect(!en.isEmpty && !fr.isEmpty)
            #expect(en != fr, "\(error) non traduit")
            for text in [en, fr] {
                #expect(!text.contains("_"), "\(error) : identifiant technique")
            }
        }
        #expect(PublishError.noCredit.offersPurchase)
    }

    @Test("Un profil simulé ne peut pas être publié")
    func simulatedCannotBePublished() throws {
        let data = try ReportCoding.encode(report(simulated: true))
        #expect(PublicationPayload.issues(in: data, secrets: []).contains("$.simulated"))
        #expect(!PublishError.simulatedProfile.message.isEmpty)
    }

    @Test("Les textes du niveau 2 ne contiennent aucun mot du lexique interdit")
    func level2Lexicon() {
        let forbidden = ["certifi", "certificat", "garanti", "authentifi", "infalsifiable", "100 % fonctionnel", "grade a", "grade b",
                         "grade c", "testé et approuvé", "warrant", "authenticat", "tamper-proof"]
        let texts = Level2Text.all
        #expect(texts.count > 30)
        for text in texts {
            let lower = text.lowercased()
            for word in forbidden {
                #expect(!lower.contains(word), "« \(word) » dans : \(text)")
            }
        }
        #expect(Level2Text.trustLevel2.contains("2"))
        #expect(Level2Text.sent.count == 6 && Level2Text.neverSent.count == 6)
    }

    @Test("Texte pour l'annonce : date et lien, rien d'autre")
    func listingText() {
        let text = Level2Text.listingText(date: "11 octobre 2026", url: "https://exemple.invalid/r/7K3P-Q2XD-M4RT")
        #expect(text.contains("11 octobre 2026") || text.contains("11 octobre 2026".replacingOccurrences(of: "octobre", with: "October")))
        #expect(text.hasSuffix("https://exemple.invalid/r/7K3P-Q2XD-M4RT"))
        #expect(Level2Text.publishedAsIs(untested: 0, blockers: 0) == nil)
        #expect(Level2Text.publishedAsIs(untested: 3, blockers: 0)?.contains("3") == true)
    }
}
