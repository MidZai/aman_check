import Testing
import Foundation
@testable import AmanCore

@Suite("Batterie")
struct BatteryAnalysisTests {
    private func find(_ list: [Measurement], _ id: String) -> Measurement? { list.first { $0.id == id } }

    @Test("MacBookPro16,1 réel : 7 270 / 8 790 mAh = 83 %, 510 cycles sur 1 000")
    func realIntelT2() {
        let registry = Fixture.batteryRegistry("battery-ioreg-MacBookPro16,1.plist")
        let power = PowerProfile(systemProfilerJSON: Fixture.data("sppower-MacBookPro16,1.json"))
        #expect(registry.designCapacity == 8790)
        #expect(registry.nominalChargeCapacity == nil)
        #expect(power?.condition == "Good")
        #expect(power?.maximumCapacityPercent == nil)

        let result = BatteryAnalysis.analyze(registry: registry, power: power, ratedCyclesFromModel: 1000)
        let health = find(result, MetricID.batteryHealth)
        #expect(health?.value == .int(83))
        #expect(health?.status == .good)
        #expect(health?.method?.contains("AppleRawMaxCapacity") == true)

        let cycles = find(result, MetricID.batteryCycles)
        #expect(cycles?.value == .int(510))
        #expect(cycles?.status == .good)
        #expect(cycles?.method?.contains("DesignCycleCount9C") == true)

        #expect(find(result, MetricID.batteryCondition)?.status == .good)
    }

    @Test("Apple Silicon : MaxCapacity en % n'est jamais pris pour des mAh")
    func appleSiliconPercentMaxCapacity() {
        // Données synthétiques (forme documentée, à remplacer par une sortie réelle d'un Mac M1).
        var r = BatteryRegistry()
        r.batteryInstalled = true
        r.designCapacity = 4382
        r.maxCapacity = 100
        r.cycleCount = 120
        let onlyPercent = BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: 1000)
        #expect(find(onlyPercent, MetricID.batteryHealth)?.status == .unavailable)
        #expect(find(onlyPercent, MetricID.batteryHealth)?.value == nil)

        r.nominalChargeCapacity = 3900
        r.appleRawMaxCapacity = 4100
        let withNominal = BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: 1000)
        let health = find(withNominal, MetricID.batteryHealth)
        #expect(health?.value == .int(89)) // 3900 / 4382, NominalChargeCapacity en priorité
        #expect(health?.method?.hasPrefix("NominalChargeCapacity") == true)
    }

    @Test("macOS affiche sa « Capacité maximale » (Apple silicon) : ce chiffre est la santé, le calcul brut va en note")
    func macOSFigureWins() {
        var r = BatteryRegistry()
        r.designCapacity = 5000
        r.appleRawMaxCapacity = 4500
        let close = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(maximumCapacityPercent: 93), ratedCyclesFromModel: nil),
                         MetricID.batteryHealth)
        #expect(close?.value == .int(93))
        #expect(close?.status == .good)
        #expect(close?.method?.contains("sppower_battery_health_maximum_capacity") == true)
        #expect(close?.note?.contains("4500 / 5000") == true)
        #expect(close?.note?.contains("90") == true)

        // Grand écart : le chiffre de macOS reste affiché et jugé, sans vérification manuelle.
        let far = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(maximumCapacityPercent: 78), ratedCyclesFromModel: nil),
                       MetricID.batteryHealth)
        #expect(far?.value == .int(78))
        #expect(far?.status == .watch)
    }

    @Test("Pas de chiffre macOS (Intel) : calcul mAh / DesignCapacity, sans note de recoupement")
    func intelComputes() {
        var r = BatteryRegistry()
        r.designCapacity = 8790
        r.appleRawMaxCapacity = 7274
        let m = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(condition: "Normal"), ratedCyclesFromModel: nil),
                     MetricID.batteryHealth)
        #expect(m?.value == .int(83))
        #expect(m?.method?.hasPrefix("AppleRawMaxCapacity") == true)
        #expect(m?.note == nil)
    }

    @Test("Seuils : ≥ 80 bon, 70–79 à surveiller, < 70 problème")
    func thresholds() {
        func status(_ current: Int) -> CheckStatus? {
            var r = BatteryRegistry()
            r.designCapacity = 1000
            r.appleRawMaxCapacity = current
            return find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryHealth)?.status
        }
        #expect(status(800) == .good)
        #expect(status(795) == .good)   // 79,5 arrondi à 80
        #expect(status(790) == .watch)
        #expect(status(700) == .watch)
        #expect(status(690) == .problem)
    }

    @Test("Valeurs incohérentes ou absentes : jamais de pourcentage inventé")
    func incoherent() {
        var r = BatteryRegistry()
        r.designCapacity = 5000
        r.appleRawMaxCapacity = 9000 // ratio 1,8
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryHealth)?.status == .unavailable)

        r.appleRawMaxCapacity = 5200 // 104 % : plafonné à 100 et noté
        let capped = find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryHealth)
        #expect(capped?.value == .int(100))
        #expect(capped?.note != nil)

        r.designCapacity = 0
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryHealth)?.value == nil)
    }

    @Test("« Service recommandé » ou défaillance permanente : problème")
    func condition() {
        var r = BatteryRegistry()
        r.designCapacity = 5000
        r.appleRawMaxCapacity = 4500
        let service = BatteryAnalysis.analyze(registry: r, power: PowerProfile(condition: "Service Recommended"), ratedCyclesFromModel: nil)
        #expect(find(service, MetricID.batteryCondition)?.status == .problem)
        #expect(find(service, MetricID.batteryHealth)?.status == .problem)

        r.permanentFailureStatus = 1
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryCondition)?.status == .problem)

        let unknown = BatteryAnalysis.analyze(registry: BatteryRegistry(), power: PowerProfile(condition: "Strange"), ratedCyclesFromModel: nil)
        #expect(find(unknown, MetricID.batteryCondition)?.status == .manualRequired)
    }

    @Test("Pas de batterie (Mac de bureau) : aucune mesure, la section disparaît")
    func noBattery() {
        #expect(BatteryAnalysis.analyze(registry: nil, power: nil, ratedCyclesFromModel: nil).isEmpty)
        var r = BatteryRegistry()
        r.batteryInstalled = false
        #expect(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil).isEmpty)
    }

    @Test("Cycles au-delà du nombre prévu : à surveiller")
    func cyclesBeyondRating() {
        var r = BatteryRegistry()
        r.cycleCount = 1050
        r.designCycleCount = 1000
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryCycles)?.status == .watch)
    }
}

@Suite("Batterie · statut rouge jamais rétrogradé")
struct BatteryStatusTests {
    private func find(_ list: [Measurement], _ id: String) -> Measurement? { list.first { $0.id == id } }

    @Test("« Service recommandé » + chiffre macOS de 82 % : reste un problème")
    func serviceRecommendedStaysProblem() {
        var r = BatteryRegistry()
        r.designCapacity = 5000
        r.appleRawMaxCapacity = 4500
        let m = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(condition: "Service Recommended", maximumCapacityPercent: 82),
                                             ratedCyclesFromModel: nil), MetricID.batteryHealth)
        #expect(m?.status == .problem)
        #expect(m?.value == .int(82))
    }

    @Test("Nombre de cycles prévu inconnu : information, pas vert")
    func unknownRatedCyclesIsInfo() {
        var r = BatteryRegistry()
        r.cycleCount = 300
        let m = find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryCycles)
        #expect(m?.status == .info)
        r.designCycleCount = 1000
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: nil), MetricID.batteryCycles)?.status == .good)
    }
}
