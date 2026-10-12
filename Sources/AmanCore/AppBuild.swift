import Foundation

/// Date de compilation de l'app, injectée par build_app.sh dans Info.plist (`AmanBuildDate`, AAAA-MM-JJ).
/// nil sous `swift run` ou si la clé manque.
public enum AppBuild {
    public static let date: Date? = {
        guard let text = Bundle.main.infoDictionary?["AmanBuildDate"] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }()

    /// Au-delà, « compatible avec le dernier macOS » ne peut plus être affirmé : la liste a pu vieillir.
    public static let freshnessLimit: TimeInterval = 18 * 30 * 86_400
}
