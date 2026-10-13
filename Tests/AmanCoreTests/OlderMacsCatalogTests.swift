import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

/// Mac antérieurs à macOS 14 (Aman Legacy) : valeurs relevées sur les fiches Apple (aman_legacy/docs/SOURCES-CATALOGUE.md).
@Suite("Catalogue : Mac anciens")
struct OlderMacsCatalogTests {
    @Test("58 modèles (62 identifiants), tous Intel, aucun compatible avec macOS 14")
    func scope() {
        let older = MacModelCatalog.olderLaptops + MacModelCatalog.olderDesktops
        #expect(older.count == 58)
        #expect(older.flatMap(\.identifiers).count == 62)
        for model in MacModelCatalog.olderLaptops + MacModelCatalog.olderDesktops {
            #expect(model.chip == .intel)
            #expect((model.lastMacOS ?? 99) <= 13, "\(model.identifiers)")
            #expect(model.hasTouchID == model.hasTouchBar, "Touch ID seulement avec la Touch Bar : \(model.identifiers)")
        }
    }

    @Test("MacBook Pro 2016–2017 : Touch Bar et Touch ID seulement sur les modèles à quatre ports et 15 pouces")
    func touchBar() {
        for id in ["MacBookPro13,1", "MacBookPro14,1"] {
            let m = MacModelCatalog.model(for: id)
            #expect(m?.hasTouchBar == false)
            #expect(m?.hasPhysicalEscape == true)
            #expect(m?.hasTouchID == false)
        }
        for id in ["MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3"] {
            let m = MacModelCatalog.model(for: id)
            #expect(m?.hasTouchBar == true)
            #expect(m?.hasPhysicalEscape == false)
            #expect(m?.hasTouchID == true)
        }
    }

    @Test("Mac de bureau sans écran : pas de caméra ; iMac10,1 : taille non renseignée")
    func desktops() {
        #expect(MacModelCatalog.model(for: "Macmini4,1")?.hasCamera == false)
        #expect(MacModelCatalog.model(for: "MacPro6,1")?.hasCamera == false)
        #expect(MacModelCatalog.model(for: "iMac10,1")?.hasCamera == true)
        #expect(MacModelCatalog.model(for: "iMac10,1")?.inches == nil)
    }

    @Test("Dernier macOS : 10.x avec sa version mineure, Mac Pro 2010–2012 selon la carte graphique")
    func lastMacOS() {
        let imac = IdentityCollector.macOSMax(MacModelCatalog.model(for: "iMac10,1"), now: Date())
        #expect(imac.value == .text("10.13"))
        #expect(imac.display == "macOS 10.13 High Sierra")
        let macPro = IdentityCollector.macOSMax(MacModelCatalog.model(for: "MacPro5,1"), now: Date())
        #expect(macPro.display == "macOS 10.14 Mojave")
        #expect(macPro.note != nil)
        #expect(IdentityCollector.macOSMax(MacModelCatalog.model(for: "MacBookAir7,2"), now: Date()).display == "macOS 12 Monterey")
        // Modèles modernes : inchangés.
        let modern = IdentityCollector.macOSMax(MacModelCatalog.model(for: "MacBookPro16,1"), now: Date())
        #expect(modern.value == .int(26))
        #expect(modern.display == "macOS 26 Tahoe")
        #expect(modern.note == nil)
    }

    @Test("Noms des versions de macOS")
    func releaseNames() {
        #expect(MacOSRelease.name(10, minor: 13) == "macOS 10.13 High Sierra")
        #expect(MacOSRelease.name(10, minor: 15) == "macOS 10.15 Catalina")
        #expect(MacOSRelease.name(11) == "macOS 11 Big Sur")
        #expect(MacOSRelease.name(14) == "macOS 14 Sonoma")
        #expect(MacOSRelease.name(15) == "macOS 15 Sequoia")
        #expect(MacOSRelease.name(26) == "macOS 26 Tahoe")
        #expect(MacOSRelease.marketingName(26) == "Tahoe")
    }
}
