import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

@Suite("Verrouillages et sécurité")
struct SecurityAnalysisTests {
    @Test("Activation Lock réel (T2) : « activation_lock_disabled » → verrou désactivé, dit explicitement, avec conseil")
    func activationLockDisabled() {
        let m = SecurityAnalysis.activationLock(hardwareJSON: Fixture.data("sphardware-MacBookPro16,1.json"), chip: .intelT2)
        #expect(m.status == .good)
        #expect(m.value == .text("activation_lock_disabled"))
        #expect(m.displayText == SecurityAnalysis.lockOff)
        #expect(m.displayText != SecurityAnalysis.noSignal)
        #expect(m.note != nil)
    }

    @Test("Activation Lock : le texte « vérification manuelle » ne contredit plus la pastille")
    func activationLockManualWording() {
        let m = SecurityAnalysis.activationLock(hardwareJSON: nil, chip: nil)
        #expect(m.status == .manualRequired)
        #expect(m.displayText == SecurityAnalysis.checkYourself)
        let intel = SecurityAnalysis.activationLock(hardwareJSON: Data(#"{"SPHardwareDataType":[{}]}"#.utf8), chip: .intel)
        #expect(intel.status == .unavailable)
        #expect(intel.displayText == SecurityAnalysis.cannotCheck)
    }

    private static func mobileMe(accounts: Int, findMy: Bool?) -> Data {
        var items = ""
        for _ in 0..<accounts {
            let service = findMy.map {
                "<dict><key>Name</key><string>FIND_MY_MAC</string><key>Enabled</key><integer>\($0 ? 1 : 0)</integer></dict>"
            } ?? ""
            items += """
            <dict>
              <key>AccountID</key><string>someone@example.com</string>
              <key>Services</key><array>
                <dict><key>Name</key><string>MOBILE_DOCUMENTS</string><key>Enabled</key><integer>1</integer></dict>
                \(service)
              </array>
            </dict>
            """
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Accounts</key><array>\(items)</array></dict></plist>
        """
        return Data(plist.utf8)
    }

    @Test("Compte Apple connecté avec Localiser : à surveiller, sans jamais exposer l'identifiant")
    func appleAccountSignedIn() {
        let m = SecurityAnalysis.appleAccount(mobileMePlist: Self.mobileMe(accounts: 1, findMy: true), domainMissing: false,
                                              chip: .intelT2, activationLockOff: true, localUserCount: 1)
        #expect(m.status == .watch)
        #expect(m.value == .int(1))
        #expect(m.detail?.contains("Localiser") == true)
        // Verrou signalé désactivé malgré Localiser sur T2 : l'explication (démarrage sécurisé) est donnée.
        #expect(m.detail?.contains("démarrage sécurisé") == true)
        let all = [m.display, m.detail, m.note, m.method].compactMap { $0 }.joined()
        #expect(!all.contains("example.com"))
        #expect(!all.contains("@"))
    }

    @Test("Compte Apple connecté, Localiser désactivé, puce Apple : pas d'explication T2")
    func appleAccountFindMyOff() {
        let m = SecurityAnalysis.appleAccount(mobileMePlist: Self.mobileMe(accounts: 2, findMy: false), domainMissing: false,
                                              chip: .appleSilicon, activationLockOff: true, localUserCount: 1)
        #expect(m.status == .watch)
        #expect(m.value == .int(2))
        #expect(m.detail?.contains("démarrage sécurisé") == false)
        #expect(m.displayText.contains("2"))
    }

    @Test("Aucun compte Apple : bon, que le domaine soit vide ou absent")
    func appleAccountNone() {
        let empty = SecurityAnalysis.appleAccount(mobileMePlist: Self.mobileMe(accounts: 0, findMy: nil), domainMissing: false,
                                                  chip: .intelT2, activationLockOff: true, localUserCount: 1)
        #expect(empty.status == .good)
        #expect(empty.value == .int(0))
        let missing = SecurityAnalysis.appleAccount(mobileMePlist: nil, domainMissing: true, chip: .appleSilicon, activationLockOff: false, localUserCount: 1)
        #expect(missing.status == .good)
    }

    @Test("Compte Apple illisible : jamais vert")
    func appleAccountUnreadable() {
        #expect(SecurityAnalysis.appleAccount(mobileMePlist: nil, domainMissing: false, chip: nil, activationLockOff: false, localUserCount: 1).status == .manualRequired)
        #expect(SecurityAnalysis.appleAccount(mobileMePlist: Data("garbage".utf8), domainMissing: false, chip: nil, activationLockOff: false, localUserCount: 1).status == .manualRequired)
    }

    @Test("Plist lisible mais sans clé Accounts : à vérifier, jamais vert")
    func appleAccountPlistWithoutAccounts() {
        let plist = Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Other</key><string>x</string></dict></plist>"#.utf8)
        #expect(SecurityAnalysis.appleAccount(mobileMePlist: plist, domainMissing: false, chip: nil, activationLockOff: false, localUserCount: 1).status == .manualRequired)
        let wrongType = Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Accounts</key><string>x</string></dict></plist>"#.utf8)
        #expect(SecurityAnalysis.appleAccount(mobileMePlist: wrongType, domainMissing: false, chip: nil, activationLockOff: false, localUserCount: 1).status == .manualRequired)
    }

    @Test("Plusieurs comptes utilisateurs locaux : seule la session en cours est vérifiée, jamais vert")
    func appleAccountSeveralLocalUsers() {
        let two = SecurityAnalysis.appleAccount(mobileMePlist: Self.mobileMe(accounts: 0, findMy: nil), domainMissing: false,
                                                chip: .appleSilicon, activationLockOff: false, localUserCount: 2)
        #expect(two.status == .manualRequired)
        #expect(two.note?.contains(L("This Mac has several user accounts.", "Ce Mac a plusieurs comptes utilisateurs.")) == true)
        let unreadable = SecurityAnalysis.appleAccount(mobileMePlist: nil, domainMissing: true, chip: .appleSilicon, activationLockOff: false, localUserCount: nil)
        #expect(unreadable.status == .manualRequired)
        let one = SecurityAnalysis.appleAccount(mobileMePlist: Self.mobileMe(accounts: 0, findMy: nil), domainMissing: false,
                                                chip: .appleSilicon, activationLockOff: false, localUserCount: 1)
        #expect(one.status == .good)
    }

    @Test("Comptes locaux comptés par dscl : UID ≥ 501 seulement")
    func localUserCount() {
        let output = "_mbsetupuser 248\nnobody -2\nroot 0\nkarim 501\nguest 502\ndaemon 1\n"
        #expect(SecurityAnalysis.localUserCount(dsclOutput: output) == 2)
        #expect(SecurityAnalysis.localUserCount(dsclOutput: "root 0\n") == 0)
        #expect(SecurityAnalysis.localUserCount(dsclOutput: nil) == nil)
        #expect(SecurityAnalysis.localUserCount(dsclOutput: "") == nil)
    }

    @Test("Activation Lock activé : signal rouge")
    func activationLockEnabled() {
        let json = #"{"SPHardwareDataType":[{"activation_lock_status":"activation_lock_enabled"}]}"#
        let m = SecurityAnalysis.activationLock(hardwareJSON: Data(json.utf8), chip: .appleSilicon)
        #expect(m.status == .problem)
    }

    @Test("Activation Lock absent : jamais vert")
    func activationLockMissing() {
        let json = #"{"SPHardwareDataType":[{"machine_model":"MacBookPro14,1"}]}"#
        #expect(SecurityAnalysis.activationLock(hardwareJSON: Data(json.utf8), chip: .intel).status == .unavailable)
        #expect(SecurityAnalysis.activationLock(hardwareJSON: Data(json.utf8), chip: .appleSilicon).status == .manualRequired)
        #expect(SecurityAnalysis.activationLock(hardwareJSON: nil, chip: nil).status == .manualRequired)
        let odd = #"{"SPHardwareDataType":[{"activation_lock_status":"something_else"}]}"#
        #expect(SecurityAnalysis.activationLock(hardwareJSON: Data(odd.utf8), chip: .intelT2).status == .manualRequired)
    }

    @Test("MDM réel : DEP non, MDM non → aucun signal, information neutre (pas un point fort)")
    func mdmNone() {
        let m = SecurityAnalysis.mdm(enrollmentOutput: Fixture.text("profiles-enrollment-none.txt"), exitCode: 0)
        #expect(m.status == .info)
        #expect(m.displayText == SecurityAnalysis.noSignal)
        #expect(m.note == SecurityAnalysis.mdmLimit)
        // Le compteur du résumé traite « information » comme neutre.
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        let report = ConditionReport(appVersion: "test", profile: profile, measurements: [m], tests: [], plannedTests: [])
        let summary = ReportSummary(report: report)
        #expect(summary.good == 0 && summary.watch == 0 && summary.problem == 0 && summary.toCheck == 0)
    }

    @Test("MDM : une réponse « Yes » suffit à remonter un signal")
    func mdmEnrolled() {
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "Enrolled via DEP: Yes\nMDM enrollment: Yes (User Approved)\n", exitCode: 0).status == .problem)
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "Enrolled via DEP: No\nMDM enrollment: Yes\n", exitCode: 0).status == .problem)
    }

    @Test("MDM : sortie inattendue ou erreur → vérification impossible, jamais vert")
    func mdmUnexpected() {
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "garbage", exitCode: 0).status == .manualRequired)
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "Enrolled via DEP: No\n", exitCode: 0).status == .manualRequired)
        #expect(SecurityAnalysis.mdm(enrollmentOutput: nil, exitCode: nil).status == .manualRequired)
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "Enrolled via DEP: No\nMDM enrollment: No\n", exitCode: 1).status == .manualRequired)
    }

    @Test("Mot de passe firmware : manuel sur Intel, sans objet sur puce Apple")
    func firmware() {
        #expect(SecurityAnalysis.firmwarePassword(chip: .intelT2).status == .manualRequired)
        #expect(SecurityAnalysis.firmwarePassword(chip: .intel).status == .manualRequired)
        #expect(SecurityAnalysis.firmwarePassword(chip: nil).status == .manualRequired)
        #expect(SecurityAnalysis.firmwarePassword(chip: .appleSilicon).status == .notApplicable)
    }

    @Test("SIP")
    func sip() {
        #expect(SecurityAnalysis.sip(csrutilOutput: Fixture.text("csrutil-enabled.txt")).status == .good)
        #expect(SecurityAnalysis.sip(csrutilOutput: "System Integrity Protection status: disabled.").status == .watch)
        #expect(SecurityAnalysis.sip(csrutilOutput: "System Integrity Protection status: unknown (Custom Configuration).").status == .watch)
        #expect(SecurityAnalysis.sip(csrutilOutput: "").status == .unavailable)
    }

    @Test("FileVault : information, jamais un jugement")
    func fileVault() {
        let m = SecurityAnalysis.fileVault(fdesetupOutput: Fixture.text("fdesetup-off.txt"))
        #expect(m.status == .info)
        #expect(m.value == .bool(false))
    }

    @Test("Machine virtuelle : rouge")
    func virtualMachine() {
        #expect(SecurityAnalysis.virtualMachine(hvVmmPresent: 1).status == .problem)
        #expect(SecurityAnalysis.virtualMachine(hvVmmPresent: 0).status == .good)
        #expect(SecurityAnalysis.virtualMachine(hvVmmPresent: nil).status == .unavailable)
    }
}

@Suite("Vie privée · sorties de commandes")
struct RawOutputPrivacyTests {
    @Test("La sortie de profiles (adresse du serveur MDM) ne va jamais dans le rapport")
    func mdmOutputIsNormalized() throws {
        let output = "Enrolled via DEP: Yes\nMDM enrollment: Yes (User Approved)\nMDM server: https://mdm.example.com/devicemanagement/\n"
        let m = SecurityAnalysis.mdm(enrollmentOutput: output, exitCode: 0)
        #expect(m.status == .problem)
        #expect(m.value == .text("dep=yes; mdm=yes"))
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        let report = ConditionReport(appVersion: "test", profile: profile, measurements: [m], tests: [], plannedTests: [])
        let json = String(decoding: try ReportCoding.encode(report), as: UTF8.self)
        #expect(!json.contains("mdm.example.com"))
        #expect(SecurityAnalysis.mdm(enrollmentOutput: "Enrolled via DEP: No\nMDM enrollment: No\n", exitCode: 0).value == .text("dep=no; mdm=no"))
    }

    @Test("csrutil : valeur normalisée, pas la ligne brute")
    func sipValueIsNormalized() {
        #expect(SecurityAnalysis.sip(csrutilOutput: "System Integrity Protection status: enabled.\n").value == .text("enabled"))
        #expect(SecurityAnalysis.sip(csrutilOutput: "System Integrity Protection status: disabled.\n").value == .text("disabled"))
        #expect(SecurityAnalysis.sip(csrutilOutput: "System Integrity Protection status: unknown (Custom Configuration).\n").value == .text("custom"))
    }
}
