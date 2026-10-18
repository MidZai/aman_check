import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

/// macOS 27 Golden Gate (retours Reddit, octobre 2026) : batterie sans pourcentage sur MacBook Air M2,
/// « compatible jusqu'à macOS 26 » sur des Mac qui font tourner macOS 27, nouveaux modèles.
@Suite("macOS 27")
struct MacOS27Tests {
    private func find(_ list: [Measurement], _ id: String) -> Measurement? { list.first { $0.id == id } }

    /// Disposition de macOS 27 (MacBook Air M2) : les capacités ne sont plus sur `AppleSmartBattery` mais dans
    /// son propre `BatteryData` et dans le nœud enfant `AppleSmartBatteryPack`. Valeurs d'un relevé publié
    /// (dépôt fixstat, BatteryLayoutTests).
    private static let top: [String: Any] = [
        "CycleCount": 479, "CurrentCapacity": 94, "MaxCapacity": 100, "ExternalConnected": true, "IsCharging": true,
        "BatteryData": ["FullChargeCapacity": 3710, "NominalChargeCapacity": 3837, "DesignCapacity": 4563,
                        "CurrentCapacity": 94, "MaxCapacity": 100] as [String: Any]
    ]
    private static let pack: [String: Any] = [
        "BatteryData": ["AppleRawMaxCapacity": 3710, "DesignCapacity": 4563, "NominalChargeCapacity": 3837,
                        "Temperature": 3159, "PermanentFailureStatus": 0] as [String: Any]
    ]

    @Test("Batterie au format macOS 27 : capacités lues dans le nœud enfant, pourcentage affiché")
    func batteryChildNodes() {
        #expect(BatteryRegistry(properties: Self.top).designCapacity == nil)   // la cause du pourcentage manquant

        let merged = BatteryRegistry.mergingChildNodes(top: Self.top, pack: Self.pack)
        let r = BatteryRegistry(properties: merged)
        #expect(r.designCapacity == 4563)
        #expect(r.nominalChargeCapacity == 3837)
        #expect(r.appleRawMaxCapacity == 3710)
        #expect(r.temperature == 3159)
        #expect(r.permanentFailureStatus == 0)
        #expect(r.cycleCount == 479)

        let health = find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: 1000), MetricID.batteryHealth)
        #expect(health?.value == .int(84))   // 3 837 / 4 563
    }

    @Test("Sans nœud enfant, le BatteryData du nœud principal suffit")
    func batteryOwnBatteryData() {
        let r = BatteryRegistry(properties: BatteryRegistry.mergingChildNodes(top: Self.top, pack: nil))
        #expect(r.designCapacity == 4563)
        #expect(r.nominalChargeCapacity == 3837)
    }

    @Test("Disposition classique (macOS 26 et avant) : rien ne change")
    func batteryClassicLayoutUntouched() {
        let classic: [String: Any] = ["DesignCapacity": 8790, "AppleRawMaxCapacity": 7270,
                                      "BatteryData": ["NominalChargeCapacity": 9999, "DesignCapacity": 1] as [String: Any]]
        let r = BatteryRegistry(properties: BatteryRegistry.mergingChildNodes(top: classic, pack: Self.pack))
        #expect(r.designCapacity == 8790)
        #expect(r.nominalChargeCapacity == nil)
        #expect(r.appleRawMaxCapacity == 7270)
    }

    @Test("Capacités en mAh illisibles : la « Capacité maximale » de macOS est reprise, présentée comme telle")
    func batteryFallsBackToMacOSFigure() {
        var r = BatteryRegistry()
        r.maxCapacity = 100
        r.cycleCount = 50
        let health = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(maximumCapacityPercent: 91), ratedCyclesFromModel: 1000),
                          MetricID.batteryHealth)
        #expect(health?.value == .int(91))
        #expect(health?.status == .good)
        #expect(health?.method?.contains("sppower_battery_health_maximum_capacity") == true)
        #expect(health?.note != nil)

        let low = find(BatteryAnalysis.analyze(registry: r, power: PowerProfile(condition: "Service Recommended", maximumCapacityPercent: 76),
                                               ratedCyclesFromModel: 1000), MetricID.batteryHealth)
        #expect(low?.status == .problem)
        // Sans aucun chiffre : toujours « Non disponible ».
        #expect(find(BatteryAnalysis.analyze(registry: r, power: nil, ratedCyclesFromModel: 1000), MetricID.batteryHealth)?.value == nil)
    }

    @Test("macOS 27 Golden Gate est la dernière version connue")
    func releaseName() {
        #expect(MacOSRelease.latestKnown == 27)
        #expect(MacOSRelease.name(27) == "macOS 27 Golden Gate")
        #expect(MacOSRelease.lastForIntel == 26)
    }

    @Test("Mac Apple silicon : compatible jusqu'à macOS 27 ; Mac Intel : s'arrêtent à macOS 26")
    func compatibility() {
        for id in ["MacBookAir10,1", "Mac14,2", "MacBookPro18,3", "Mac15,4", "Mac16,10", "Mac14,8"] {
            let m = IdentityCollector.macOSMax(MacModelCatalog.model(for: id), now: Date(), latest: 27)
            #expect(m.display == "macOS 27 Golden Gate", "\(id)")
        }
        for model in MacModelCatalog.laptops + MacModelCatalog.desktops {
            if model.chip == .appleSilicon {
                #expect(model.lastMacOS == nil, "\(model.identifiers)")
            } else {
                #expect((model.lastMacOS ?? 99) <= 26, "\(model.identifiers)")
            }
        }
        let intel = IdentityCollector.macOSMax(MacModelCatalog.model(for: "MacBookPro16,1"), now: Date(), latest: 27)
        #expect(intel.display == "macOS 26 Tahoe")
        #expect(intel.detail == L("Will not receive macOS 27 Golden Gate", "Ne recevra pas macOS 27 Golden Gate"))
    }

    @Test("Version de macOS plus récente que celle connue de l'app : c'est elle qui est affichée")
    func newerRunningMacOS() {
        let m = IdentityCollector.macOSMax(MacModelCatalog.model(for: "Mac14,2"), now: Date(), latest: MacOSRelease.reference(runningMajor: 28))
        #expect(m.display == "macOS 28")
        #expect(m.value == .int(28))
    }

    @Test("Mac sortis en 2025 et 2026 (pages Apple « Identifier votre Mac »)")
    func newModels() {
        // identifiant : (famille, pouces, année)
        let expected: [String: (String, Int?, Int)] = [
            "Mac17,2": ("MacBook Pro", 14, 2025),
            "Mac17,7": ("MacBook Pro", 14, 2026), "Mac17,9": ("MacBook Pro", 14, 2026),
            "Mac17,6": ("MacBook Pro", 16, 2026), "Mac17,8": ("MacBook Pro", 16, 2026),
            "Mac17,3": ("MacBook Air", 13, 2026), "Mac17,4": ("MacBook Air", 15, 2026),
            "Mac17,5": ("MacBook Neo", 13, 2026),
            "Mac17,16": ("Mac mini", nil, 2026), "Mac18,5": ("Mac mini", nil, 2026),
            "Mac17,14": ("Mac Studio", nil, 2026), "Mac17,15": ("Mac Studio", nil, 2026)
        ]
        for (id, (family, inches, year)) in expected {
            let model = MacModelCatalog.model(for: id)
            #expect(model?.family == family, "\(id)")
            #expect(model?.inches == inches, "\(id)")
            #expect(model?.year == year, "\(id)")
            #expect(model?.chip == .appleSilicon, "\(id)")
            #expect(model?.lastMacOS == nil, "\(id)")
        }
        #expect(MacModelCatalog.model(for: "Mac17,2")?.variant == "M5")
        #expect(MacModelCatalog.model(for: "Mac17,3")?.variant == "M5")
        #expect(MacModelCatalog.model(for: "Mac18,5")?.variant == "M6")
        #expect(MacModelCatalog.model(for: "Mac17,15")?.variant == "M5 Ultra")
    }

    @Test("MacBook Neo : ni rétroéclairage, ni capteur de luminosité, ni Force Touch ; Touch ID selon la configuration")
    func macBookNeo() {
        let p = DeviceProfile.make(modelIdentifier: "Mac17,5", simulated: true)
        #expect(p.isLaptop)
        #expect(!p.hasKeyboardBacklight)
        #expect(!p.hasAmbientLightSensor)
        #expect(!p.trackpadForceTouch)
        #expect(p.hasFan == nil)   // non précisé par Apple : pas de jugement sur le ventilateur
        #expect(!p.hasTouchID)
        #expect(p.model?.ratedBatteryCycles == 1000)
        // Touch ID détecté (configuration 512 Go) : présent ; non détecté (256 Go) : pas signalé comme manquant.
        #expect(DeviceProfile.make(modelIdentifier: "Mac17,5", detected: .init(hasBattery: true, hasBiometrics: true)).hasTouchID)
        #expect(DeviceProfile.make(modelIdentifier: "Mac17,5", detected: .init(hasBattery: true, hasBiometrics: false)).missingComponents == nil)
        // Portable classique : inchangé.
        let air = DeviceProfile.make(modelIdentifier: "Mac14,2", simulated: true)
        #expect(air.hasKeyboardBacklight && air.hasAmbientLightSensor && air.trackpadForceTouch && air.hasFan == false)
    }
}
