import Foundation

/// `system_profiler <type> -json`. L'option `-json` n'existe qu'à partir de macOS 10.15 : avant (Aman Legacy),
/// la sortie `-xml` est convertie au même JSON, `{ "<type>": [éléments] }`, pour que les mêmes analyses servent.
/// Mêmes clés et mêmes valeurs (vérifié sur un MacBookPro16,1, fixtures sp*-MacBookPro16,1) ; seuls les dates
/// et les blocs binaires, qu'aucune analyse ne lit, s'écrivent différemment.
public enum SystemProfiler {
    public static let path = "/usr/sbin/system_profiler"

    public static func runSync(_ dataType: String, timeout: TimeInterval = 15) -> CommandResult? {
        if #available(macOS 10.15, *) {
            return Shell.runSync(path, [dataType, "-json"], timeout: timeout)
        }
        guard let xml = Shell.runSync(path, [dataType, "-xml"], timeout: timeout) else { return nil }
        return CommandResult(stdout: jsonText(fromXML: Data(xml.stdout.utf8)) ?? "", stderr: xml.stderr, exitCode: xml.exitCode)
    }

    /// Sortie `-xml` (tableau de `{ _dataType, _items }`) → texte JSON de la sortie `-json`. `nil` si illisible.
    public static func jsonText(fromXML data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return nil }
        var root: [String: Any] = [:]
        for entry in plist {
            guard let type = entry["_dataType"] as? String else { continue }
            root[type] = jsonCompatible(entry["_items"] ?? [])
        }
        guard let json = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: json, encoding: .utf8)
    }

    /// Les plists peuvent contenir des dates et des données binaires, que JSON n'a pas.
    private static func jsonCompatible(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]: return dict.mapValues(jsonCompatible)
        case let array as [Any]: return array.map(jsonCompatible)
        case let date as Date: return iso8601.string(from: date)
        case let data as Data: return data.map { String(format: "%02x", $0) }.joined()
        default: return value
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
