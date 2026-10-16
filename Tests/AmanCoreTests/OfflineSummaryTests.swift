import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

@Suite("QR code hors ligne · résumé compact")
struct OfflineSummaryTests {
    private func report(_ measurements: [Measurement], model: String = "MacBookPro16,1", tests: [TestResult] = []) -> ConditionReport {
        let profile = DeviceProfile.make(modelIdentifier: model, simulated: false)
        return ConditionReport(reportID: "AC-7K3P-Q2XD", generatedAt: Date(timeIntervalSince1970: 1_792_150_000), appVersion: "test",
                               profile: profile, measurements: measurements, tests: tests, plannedTests: TestID.applicable(to: profile))
    }

    private var fullMeasurements: [Measurement] {
        [Measurement(id: MetricID.serial, value: .text("C02ZK1ABMD6T"), status: .info, display: "••••MD6T"),
         Measurement(id: MetricID.batteryCycles, value: .int(511), status: .good),
         Measurement(id: MetricID.batteryHealth, value: .int(83), status: .good),
         Measurement(id: MetricID.storagePowerOnHours, value: .int(3538), status: .info),
         Measurement(id: MetricID.activationLock, value: .text("activation_lock_disabled"), status: .good),
         Measurement(id: MetricID.mdm, value: .text("no"), status: .info),
         Measurement(id: MetricID.appleAccount, value: .int(1), status: .watch)]
    }

    @Test("Contenu : schéma, date, modèle, cycles, capacité, heures SSD, verrous, compteurs")
    func content() {
        let text = OfflineSummary.text(for: report(fullMeasurements))
        let lines = Set(text.split(separator: "\n").map(String.init))
        #expect(text.hasPrefix("AMAN CHECK SUMMARY v1\n"))
        #expect(lines.contains { $0.hasPrefix("date=") })
        #expect(lines.contains("report=AC-7K3P-Q2XD"))
        #expect(lines.contains("model=MacBookPro16,1"))
        #expect(lines.contains("battery_cycles=511"))
        #expect(lines.contains("battery_capacity=83%"))
        #expect(lines.contains("ssd_hours=3538"))
        #expect(lines.contains("activation_lock=off"))
        #expect(lines.contains("mdm=no signal"))
        #expect(lines.contains("apple_account=SIGNED IN"))
        #expect(lines.contains { $0.hasPrefix("counts=good ") && $0.contains("not tested") })
        #expect(lines.contains { $0.hasPrefix("tests=0/") })
        // Aucune URL : le code ne renvoie vers aucun serveur.
        #expect(!text.contains("http"))
    }

    @Test("Numéro de série : 4 derniers caractères seulement, même si la valeur stockée est plus longue")
    func serialTruncated() {
        let text = OfflineSummary.text(for: report(fullMeasurements))
        #expect(text.contains("serial_last4=MD6T\n"))
        #expect(!text.contains("C02ZK1AB"))
        #expect(!text.contains("ZK1ABMD6T"))
    }

    @Test("Taille : moins de 500 caractères, même avec un nom de vendeur et tous les champs")
    func length() {
        var r = report(fullMeasurements)
        r.sellerName = String(repeating: "Boutique très longue ", count: 20)
        let text = OfflineSummary.text(for: r)
        #expect(text.count < OfflineSummary.maximumLength)
        // Le nom du vendeur n'est pas dans le code : il n'appartient pas au résumé technique.
        #expect(!text.contains("Boutique"))
    }

    @Test("Valeurs absentes : « n/a » ou « not verified », jamais une valeur inventée")
    func missingValues() {
        let text = OfflineSummary.text(for: report([
            Measurement.unavailable(MetricID.batteryHealth, note: "x"),
            Measurement(id: MetricID.activationLock, value: nil, status: .manualRequired),
            Measurement(id: MetricID.mdm, value: .text("yes"), status: .problem)
        ]))
        #expect(text.contains("battery_capacity=n/a"))
        #expect(text.contains("battery_cycles=n/a"))
        #expect(text.contains("ssd_hours=n/a"))
        #expect(text.contains("activation_lock=not verified"))
        #expect(text.contains("mdm=ENROLLED"))
        #expect(text.contains("apple_account=not verified"))
        #expect(!text.contains("serial_last4="))
    }

    @Test("Mac de bureau : pas de ligne batterie")
    func desktop() {
        let text = OfflineSummary.text(for: report([], model: "Macmini9,1"))
        #expect(!text.contains("battery_"))
        #expect(text.contains("model=Macmini9,1"))
    }
}
