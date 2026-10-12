import Foundation
@testable import AmanCore

typealias Measurement = AmanCore.Measurement

enum Fixture {
    static func url(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            fatalError("Fixture manquante : \(name)")
        }
        return url
    }

    static func data(_ name: String) -> Data {
        (try? Data(contentsOf: url(name))) ?? Data()
    }

    static func text(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }

    /// `ioreg -rn AppleSmartBattery -a` : tableau plist d'un dictionnaire.
    static func batteryRegistry(_ name: String) -> BatteryRegistry {
        let plist = try? PropertyListSerialization.propertyList(from: data(name), format: nil)
        let dict = (plist as? [[String: Any]])?.first ?? [:]
        return BatteryRegistry(properties: dict)
    }
}
