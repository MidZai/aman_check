import Testing
import Foundation
@testable import AmanCore

/// Niveau 2, phase 0 : les quatre corrections préalables (cahier des charges §8).
@Suite("Niveau 2 · prérequis")
struct PrerequisiteTests {
    @Test("Un rapport ne porte jamais des tests terminés avant le lancement du contrôle")
    func testsBeforeAnalysisAreDropped() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let before = TestResult(test: .screen, outcome: .passed, provenance: .userObserved, summary: "ok",
                                completedAt: start.addingTimeInterval(-60))
        let after = TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "65/65",
                               completedAt: start.addingTimeInterval(120))
        let kept = TestResult.belonging(toAnalysisStartedAt: start, [before, after])
        #expect(kept.map(\.test) == [.keyboard])
        // Aucun contrôle lancé : aucun test ne peut appartenir à un rapport.
        #expect(TestResult.belonging(toAnalysisStartedAt: nil, [before, after]).isEmpty)
    }

    @Test("Profil simulé inscrit dans le rapport (champ simulated) et relu depuis le JSON")
    func simulatedIsRecorded() throws {
        let simulated = DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
        let real = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        let r = ConditionReport(appVersion: "test", profile: simulated, measurements: [], tests: [], plannedTests: [])
        #expect(r.simulated)
        #expect(!ConditionReport(appVersion: "test", profile: real, measurements: [], tests: [], plannedTests: []).simulated)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(r), as: UTF8.self)
        #expect(json.contains(#""simulated":true"#))
        #expect(try JSONDecoder().decode(ConditionReport.self, from: Data(json.utf8)).simulated)
        #expect(!ReportText.simulatedWarning.isEmpty)
    }

    @Test("Rapport antérieur au champ simulated : relu sans erreur, le profil fait foi")
    func legacyReportDecodes() throws {
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        let r = ConditionReport(appVersion: "test", profile: profile, measurements: [], tests: [], plannedTests: [])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as! [String: Any]
        object.removeValue(forKey: "simulated")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ConditionReport.self, from: legacy).simulated == false)
    }

    @Test("Clavier : bloqué par un clavier externe, pas par le clavier intégré ni la Touch Bar")
    func keyboardGate() {
        let internalKeyboard = HIDDeviceInfo(name: "Apple Internal Keyboard / Trackpad", kind: .keyboard, isBuiltIn: true, transport: "USB")
        let internalTrackpad = HIDDeviceInfo(name: "Apple Internal Keyboard / Trackpad", kind: .pointer, isBuiltIn: true, transport: "USB")
        let touchBar = HIDDeviceInfo(name: "TouchBarUserDevice", kind: .keyboard, isBuiltIn: true, transport: "Virtual")
        let magicKeyboard = HIDDeviceInfo(name: "Magic Keyboard", kind: .keyboard, isBuiltIn: false, transport: "Bluetooth")
        let mouse = HIDDeviceInfo(name: "USB Mouse", kind: .pointer, isBuiltIn: false, transport: "USB")

        #expect(ExternalInputGuard.blockers(for: .keyboard, devices: [internalKeyboard, internalTrackpad, touchBar]).isEmpty)
        #expect(ExternalInputGuard.blockers(for: .keyboard, devices: [internalKeyboard, magicKeyboard, mouse]) == ["Magic Keyboard"])
        // Une souris ne bloque pas le test du clavier.
        #expect(ExternalInputGuard.blockers(for: .keyboard, devices: [internalKeyboard, mouse]).isEmpty)
    }

    @Test("Trackpad : bloqué par une souris ou un trackpad externe, pas par le trackpad intégré")
    func trackpadGate() {
        let internalTrackpad = HIDDeviceInfo(name: "Apple Internal Keyboard / Trackpad", kind: .pointer, isBuiltIn: true, transport: "USB")
        let mouse = HIDDeviceInfo(name: "USB Mouse", kind: .pointer, isBuiltIn: false, transport: "USB")
        let magicTrackpad = HIDDeviceInfo(name: "Magic Trackpad", kind: .pointer, isBuiltIn: false, transport: "Bluetooth")
        let magicKeyboard = HIDDeviceInfo(name: "Magic Keyboard", kind: .keyboard, isBuiltIn: false, transport: "Bluetooth")

        #expect(ExternalInputGuard.blockers(for: .trackpad, devices: [internalTrackpad]).isEmpty)
        #expect(ExternalInputGuard.blockers(for: .trackpad, devices: [internalTrackpad, mouse, magicTrackpad, mouse]) == ["USB Mouse", "Magic Trackpad"])
        #expect(ExternalInputGuard.blockers(for: .trackpad, devices: [internalTrackpad, magicKeyboard]).isEmpty)
        #expect(ExternalInputGuard.blockers(for: .screen, devices: [mouse, magicKeyboard]).isEmpty)
    }

    @Test("Export de diagnostic : numéros de série de la batterie, du Mac, des écrans et UUID masqués")
    func diagnosticRedaction() {
        let power = Redaction.identifiers(in: Fixture.text("sppower-MacBookPro16,1.json"))
        #expect(power.contains(#""sppower_battery_serial_number" : "•••""#))
        #expect(!power.contains("ANONYMIZED"))
        // Les autres valeurs restent lisibles.
        #expect(power.contains("sppower_battery_health"))

        let hardware = Redaction.identifiers(in: Fixture.text("sphardware-MacBookPro16,1.json"))
        #expect(!hardware.contains("ANONYMIZED"))

        let synthetic = """
        {"_spdisplays_display-serial-number" : "4C2A9F11", "platform_UUID": "1234-ABCD", "provisioning_UDID": "0000", "model": "Studio Display"}
        Serial Number (system): C02ZK1ABCDEF
        Hardware UUID: 1234
        Model Name: MacBook Pro
        """
        let out = Redaction.identifiers(in: synthetic)
        for secret in ["4C2A9F11", "1234-ABCD", "0000", "C02ZK1ABCDEF", "Hardware UUID: 1234"] {
            #expect(!out.contains(secret), "\(secret) non masqué")
        }
        #expect(out.contains("Studio Display"))
        #expect(out.contains("Model Name: MacBook Pro"))
    }
}
