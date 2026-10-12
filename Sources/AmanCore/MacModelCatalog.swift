import Foundation
import DiskHealthCore

public enum MacKind: String, Codable, Sendable {
    case laptop, iMac, mini, studio, pro, unknown

    public var isDesktop: Bool { self == .iMac || self == .mini || self == .studio || self == .pro }

    /// SF Symbol du visuel de l'app (correctifs §3.5, option 2).
    public var symbolName: String {
        switch self {
        case .laptop: return "laptopcomputer"
        case .iMac: return "desktopcomputer"
        case .mini: return "macmini"
        case .studio: return "macstudio"
        case .pro: return "macpro.gen3"
        case .unknown: return "desktopcomputer"
        }
    }
}

public enum ChipFamily: String, Codable, Sendable {
    case intel          // Intel sans puce T2
    case intelT2        // Intel avec puce de sécurité T2 (2018–2020)
    case appleSilicon
}

/// Fiche d'un modèle de Mac. Seuls les modèles capables de faire tourner l'app
/// (macOS 14 Sonoma ou plus récent, comme Aman Disk) sont listés.
///
/// Sources : pages d'assistance Apple « Identifier votre MacBook Pro / MacBook Air / iMac /
/// Mac mini / Mac Studio / Mac Pro » et listes de compatibilité de macOS 14, 15 et 26.
/// TODO: à revérifier à chaque nouvelle version de macOS (macOS maximal) et à chaque nouveau Mac.
public struct MacModel: Codable, Sendable, Hashable {
    public let identifiers: [String]
    public let family: String           // « MacBook Pro » (nom commercial Apple, non traduit)
    public let inches: Int?
    public let year: Int
    /// Même identifiant vendu deux années de suite (MacBookPro15,1 : 2018 et 2019).
    public let alsoYear: Int?
    public let variant: String?         // « M1 Pro ou M1 Max », « quatre ports Thunderbolt 3 »…
    public let kind: MacKind
    public let chip: ChipFamily
    public let hasTouchBar: Bool
    /// Touche Échap physique (les MacBook Pro Touch Bar 2016–2019 15″/13″ l'ont dans la Touch Bar).
    public let hasPhysicalEscape: Bool
    public let hasTouchID: Bool
    public let hasCamera: Bool
    /// Ports USB-C / Thunderbolt du boîtier. `nil` : non renseigné, aucun total affiché.
    public let thunderboltPorts: Int?
    public let hasHDMI: Bool
    public let hasSDSlot: Bool
    public let hasMagSafe: Bool
    /// Dernière version majeure de macOS pour ce modèle ; `nil` : encore pris en charge par la plus récente.
    public let lastMacOS: Int?
    /// Cycles de charge pour lesquels la batterie est conçue (Apple : 1 000 pour les portables récents).
    public let ratedBatteryCycles: Int?

    public var yearText: String {
        guard let alsoYear else { return String(year) }
        return L("\(year) or \(alsoYear)", "\(year) ou \(alsoYear)")
    }

    public var isLaptop: Bool { kind == .laptop }
    public var hasFunctionRow: Bool { isLaptop && !hasTouchBar }

    /// « MacBook Pro (16 pouces, 2019) », comme dans « À propos de ce Mac ».
    public var displayName: String {
        var parts: [String] = []
        if let inches { parts.append(L("\(inches)-inch", "\(inches) pouces")) }
        if let variant { parts.append(variant) }
        parts.append(yearText)
        return "\(family) (\(parts.joined(separator: ", ")))"
    }
}

/// Noms commerciaux des versions de macOS.
public enum MacOSRelease {
    /// Dernière version majeure connue de cette version de l'app.
    public static let latestKnown = 26
    /// Dernière version majeure annoncée par Apple pour les Mac Intel (WWDC 2025).
    public static let lastForIntel = 26

    public static func name(_ major: Int) -> String {
        switch major {
        case 14: return "macOS 14 Sonoma"
        case 15: return "macOS 15 Sequoia"
        case 26: return "macOS 26 Tahoe"
        default: return "macOS \(major)"
        }
    }
}

public enum MacModelCatalog {
    public static func model(for identifier: String) -> MacModel? {
        byIdentifier[identifier]
    }

    public static let all: [MacModel] = laptops + desktops

    private static let byIdentifier: [String: MacModel] = {
        var map: [String: MacModel] = [:]
        for model in all {
            for id in model.identifiers {
                assert(map[id] == nil, "Identifiant en double : \(id)")
                map[id] = model
            }
        }
        return map
    }()

    // MARK: - Portables

    private static func laptop(_ ids: [String], _ family: String, inches: Int, year: Int, alsoYear: Int? = nil, variant: String? = nil,
                               chip: ChipFamily, touchBar: Bool = false, physicalEscape: Bool = true,
                               ports: Int, hdmi: Bool = false, sd: Bool = false, magSafe: Bool = false,
                               lastMacOS: Int? = nil) -> MacModel {
        MacModel(identifiers: ids, family: family, inches: inches, year: year, alsoYear: alsoYear, variant: variant, kind: .laptop,
                 chip: chip, hasTouchBar: touchBar, hasPhysicalEscape: physicalEscape,
                 // Tous les portables listés ici ont Touch ID et une caméra FaceTime HD.
                 hasTouchID: true, hasCamera: true,
                 thunderboltPorts: ports, hasHDMI: hdmi, hasSDSlot: sd, hasMagSafe: magSafe,
                 lastMacOS: lastMacOS, ratedBatteryCycles: 1000)
    }

    static let laptops: [MacModel] = [
        // MacBook Air Intel
        laptop(["MacBookAir8,1"], "MacBook Air", inches: 13, year: 2018, chip: .intelT2, ports: 2, lastMacOS: 14),
        laptop(["MacBookAir8,2"], "MacBook Air", inches: 13, year: 2019, chip: .intelT2, ports: 2, lastMacOS: 14),
        laptop(["MacBookAir9,1"], "MacBook Air", inches: 13, year: 2020, chip: .intelT2, ports: 2, lastMacOS: 15),
        // MacBook Air Apple Silicon
        laptop(["MacBookAir10,1"], "MacBook Air", inches: 13, year: 2020, variant: "M1", chip: .appleSilicon, ports: 2),
        laptop(["Mac14,2"], "MacBook Air", inches: 13, year: 2022, variant: "M2", chip: .appleSilicon, ports: 2, magSafe: true),
        laptop(["Mac14,15"], "MacBook Air", inches: 15, year: 2023, variant: "M2", chip: .appleSilicon, ports: 2, magSafe: true),
        laptop(["Mac15,12"], "MacBook Air", inches: 13, year: 2024, variant: "M3", chip: .appleSilicon, ports: 2, magSafe: true),
        laptop(["Mac15,13"], "MacBook Air", inches: 15, year: 2024, variant: "M3", chip: .appleSilicon, ports: 2, magSafe: true),
        laptop(["Mac16,12"], "MacBook Air", inches: 13, year: 2025, variant: "M4", chip: .appleSilicon, ports: 2, magSafe: true),
        laptop(["Mac16,13"], "MacBook Air", inches: 15, year: 2025, variant: "M4", chip: .appleSilicon, ports: 2, magSafe: true),

        // MacBook Pro Intel (Touch Bar)
        laptop(["MacBookPro15,1"], "MacBook Pro", inches: 15, year: 2018, alsoYear: 2019, chip: .intelT2, touchBar: true, physicalEscape: false, ports: 4, lastMacOS: 15),
        laptop(["MacBookPro15,3"], "MacBook Pro", inches: 15, year: 2019, chip: .intelT2, touchBar: true, physicalEscape: false, ports: 4, lastMacOS: 15),
        laptop(["MacBookPro15,2"], "MacBook Pro", inches: 13, year: 2018, alsoYear: 2019, variant: L("four Thunderbolt 3 ports", "quatre ports Thunderbolt 3"), chip: .intelT2, touchBar: true, physicalEscape: false, ports: 4, lastMacOS: 15),
        laptop(["MacBookPro15,4"], "MacBook Pro", inches: 13, year: 2019, variant: L("two Thunderbolt 3 ports", "deux ports Thunderbolt 3"), chip: .intelT2, touchBar: true, physicalEscape: false, ports: 2, lastMacOS: 15),
        laptop(["MacBookPro16,1", "MacBookPro16,4"], "MacBook Pro", inches: 16, year: 2019, chip: .intelT2, touchBar: true, ports: 4, lastMacOS: 26),
        laptop(["MacBookPro16,2"], "MacBook Pro", inches: 13, year: 2020, variant: L("four Thunderbolt 3 ports", "quatre ports Thunderbolt 3"), chip: .intelT2, touchBar: true, ports: 4, lastMacOS: 26),
        laptop(["MacBookPro16,3"], "MacBook Pro", inches: 13, year: 2020, variant: L("two Thunderbolt 3 ports", "deux ports Thunderbolt 3"), chip: .intelT2, touchBar: true, ports: 2, lastMacOS: 15),
        // MacBook Pro Apple Silicon
        laptop(["MacBookPro17,1"], "MacBook Pro", inches: 13, year: 2020, variant: "M1", chip: .appleSilicon, touchBar: true, ports: 2),
        laptop(["Mac14,7"], "MacBook Pro", inches: 13, year: 2022, variant: "M2", chip: .appleSilicon, touchBar: true, ports: 2),
        laptop(["MacBookPro18,3", "MacBookPro18,4"], "MacBook Pro", inches: 14, year: 2021, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["MacBookPro18,1", "MacBookPro18,2"], "MacBook Pro", inches: 16, year: 2021, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac14,5", "Mac14,9"], "MacBook Pro", inches: 14, year: 2023, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac14,6", "Mac14,10"], "MacBook Pro", inches: 16, year: 2023, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac15,3"], "MacBook Pro", inches: 14, year: 2023, variant: "M3", chip: .appleSilicon, ports: 2, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac15,6", "Mac15,8", "Mac15,10"], "MacBook Pro", inches: 14, year: 2023, variant: L("M3 Pro or M3 Max", "M3 Pro ou M3 Max"), chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac15,7", "Mac15,9", "Mac15,11"], "MacBook Pro", inches: 16, year: 2023, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac16,1"], "MacBook Pro", inches: 14, year: 2024, variant: "M4", chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac16,6", "Mac16,8"], "MacBook Pro", inches: 14, year: 2024, variant: L("M4 Pro or M4 Max", "M4 Pro ou M4 Max"), chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true),
        laptop(["Mac16,5", "Mac16,7"], "MacBook Pro", inches: 16, year: 2024, chip: .appleSilicon, ports: 3, hdmi: true, sd: true, magSafe: true)
    ]

    // MARK: - Mac de bureau

    private static func desktop(_ ids: [String], _ family: String, kind: MacKind, inches: Int? = nil, year: Int, alsoYear: Int? = nil,
                                variant: String? = nil, chip: ChipFamily, camera: Bool, hdmi: Bool = false,
                                sd: Bool = false, lastMacOS: Int? = nil) -> MacModel {
        MacModel(identifiers: ids, family: family, inches: inches, year: year, alsoYear: alsoYear, variant: variant, kind: kind,
                 chip: chip, hasTouchBar: false, hasPhysicalEscape: false, hasTouchID: false, hasCamera: camera,
                 // Ports des Mac de bureau non renseignés : pas de total affiché (correctifs §6.6).
                 thunderboltPorts: nil, hasHDMI: hdmi, hasSDSlot: sd, hasMagSafe: false,
                 lastMacOS: lastMacOS, ratedBatteryCycles: nil)
    }

    static let desktops: [MacModel] = [
        desktop(["iMac19,1"], "iMac", kind: .iMac, inches: 27, year: 2019, chip: .intel, camera: true, sd: true, lastMacOS: 15),
        desktop(["iMac19,2"], "iMac", kind: .iMac, year: 2019, variant: L("21.5-inch, Retina 4K", "21,5 pouces, Retina 4K"), chip: .intel, camera: true, sd: true, lastMacOS: 15),
        desktop(["iMac20,1", "iMac20,2"], "iMac", kind: .iMac, inches: 27, year: 2020, chip: .intelT2, camera: true, sd: true, lastMacOS: 26),
        desktop(["iMacPro1,1"], "iMac Pro", kind: .iMac, year: 2017, chip: .intelT2, camera: true, sd: true, lastMacOS: 15),
        desktop(["iMac21,1", "iMac21,2"], "iMac", kind: .iMac, inches: 24, year: 2021, variant: "M1", chip: .appleSilicon, camera: true),
        desktop(["Mac15,4", "Mac15,5"], "iMac", kind: .iMac, inches: 24, year: 2023, variant: "M3", chip: .appleSilicon, camera: true),
        desktop(["Mac16,2", "Mac16,3"], "iMac", kind: .iMac, inches: 24, year: 2024, variant: "M4", chip: .appleSilicon, camera: true),

        desktop(["Macmini8,1"], "Mac mini", kind: .mini, year: 2018, chip: .intelT2, camera: false, hdmi: true, lastMacOS: 15),
        desktop(["Macmini9,1"], "Mac mini", kind: .mini, year: 2020, variant: "M1", chip: .appleSilicon, camera: false, hdmi: true),
        desktop(["Mac14,3", "Mac14,12"], "Mac mini", kind: .mini, year: 2023, chip: .appleSilicon, camera: false, hdmi: true),
        desktop(["Mac16,10", "Mac16,11"], "Mac mini", kind: .mini, year: 2024, chip: .appleSilicon, camera: false, hdmi: true),

        desktop(["Mac13,1", "Mac13,2"], "Mac Studio", kind: .studio, year: 2022, chip: .appleSilicon, camera: false, hdmi: true, sd: true),
        desktop(["Mac14,13", "Mac14,14"], "Mac Studio", kind: .studio, year: 2023, chip: .appleSilicon, camera: false, hdmi: true, sd: true),
        desktop(["Mac15,14", "Mac16,9"], "Mac Studio", kind: .studio, year: 2025, chip: .appleSilicon, camera: false, hdmi: true, sd: true),

        desktop(["MacPro7,1"], "Mac Pro", kind: .pro, year: 2019, chip: .intelT2, camera: false, lastMacOS: 26),
        desktop(["Mac14,8"], "Mac Pro", kind: .pro, year: 2023, chip: .appleSilicon, camera: false, hdmi: true)
    ]
}
