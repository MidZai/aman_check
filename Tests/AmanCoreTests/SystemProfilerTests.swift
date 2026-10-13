import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

/// Repli `-xml` de `system_profiler` (Aman Legacy, avant macOS 10.15) : la conversion doit redonner le JSON de `-json`.
/// Paires capturées au même moment sur un MacBookPro16,1 (Fixtures/xml-pairs, identifiants anonymisés).
@Suite("system_profiler : repli XML")
struct SystemProfilerTests {
    private func pair(_ name: String) -> (json: String, converted: String?) {
        (Fixture.text("xml-pairs/\(name).json"), SystemProfiler.jsonText(fromXML: Fixture.data("xml-pairs/\(name).xml")))
    }

    private func object(_ text: String?) -> Any? {
        text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
    }

    /// Égalité profonde, sauf les valeurs que macOS écrit différemment selon le format (dates)
    /// ou qui changent d'une lecture à l'autre (registre de l'écran) : aucune analyse ne les lit.
    private func same(_ a: Any?, _ b: Any?, ignoring: Set<String>) -> Bool {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            let keys = Set(x.keys).union(y.keys).subtracting(ignoring)
            return keys.allSatisfy { same(x[$0], y[$0], ignoring: ignoring) }
        case let (x as [Any], y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy { same($0, $1, ignoring: ignoring) }
        case let (x as NSNumber, y as NSNumber):
            return x == y
        case let (x as String, y as String):
            return x == y
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    @Test("Même JSON que -json, pour la batterie, le matériel et l'écran", arguments: ["sppower", "sphardware", "spdisplays"])
    func convertedXMLMatchesJSON(name: String) {
        let (json, converted) = pair(name)
        #expect(converted != nil)
        #expect(same(object(json), object(converted), ignoring: ["time", "_spdisplays_displayRegID"]))
    }

    @Test("Mêmes analyses à partir du XML converti")
    func sameAnalyses() {
        let power = pair("sppower")
        let fromJSON = PowerProfile(systemProfilerJSON: Data(power.json.utf8))
        #expect(fromJSON != nil)
        #expect(PowerProfile(systemProfilerJSON: Data((power.converted ?? "").utf8)) == fromJSON)

        let hardware = pair("sphardware")
        let lockJSON = SecurityAnalysis.activationLock(hardwareJSON: Data(hardware.json.utf8), chip: .intelT2)
        let lockXML = SecurityAnalysis.activationLock(hardwareJSON: hardware.converted.map { Data($0.utf8) }, chip: .intelT2)
        #expect(lockXML.status == lockJSON.status)
        #expect(lockXML.displayText == lockJSON.displayText)

        let displays = pair("spdisplays")
        let screensJSON = DisplaysParser.parse(displays.json)
        let screensXML = DisplaysParser.parse(displays.converted)
        #expect(screensJSON.gpu != nil)
        #expect(screensXML.gpu?.name == screensJSON.gpu?.name)
        #expect(screensXML.gpu?.detail == screensJSON.gpu?.detail)
        #expect(screensXML.builtInDisplay?.name == screensJSON.builtInDisplay?.name)
    }

    @Test("Dates et données binaires du plist deviennent du texte JSON")
    func plistOnlyTypes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><array><dict>
          <key>_dataType</key><string>SPTestDataType</string>
          <key>_items</key><array><dict>
            <key>when</key><date>2026-10-13T12:42:53Z</date>
            <key>blob</key><data>AP8=</data>
            <key>count</key><integer>3</integer>
          </dict></array>
        </dict></array></plist>
        """
        let text = try #require(SystemProfiler.jsonText(fromXML: Data(xml.utf8)))
        let root = try #require(object(text) as? [String: Any])
        let item = try #require((root["SPTestDataType"] as? [[String: Any]])?.first)
        #expect(item["when"] as? String == "2026-10-13T12:42:53Z")
        #expect(item["blob"] as? String == "00ff")
        #expect(item["count"] as? Int == 3)
        #expect(SystemProfiler.jsonText(fromXML: Data("pas un plist".utf8)) == nil)
    }
}
