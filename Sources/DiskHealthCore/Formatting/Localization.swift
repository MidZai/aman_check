import Foundation

/// Interface language. Supports 18 languages:
/// French, English, Mandarin Chinese (Simplified), Chinese (Traditional),
/// Korean, Arabic, Portuguese, Spanish, German, Italian, Japanese,
/// Russian, Turkish, Dutch, Polish, Hindi, Vietnamese, Ukrainian.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case french = "fr"          // Français
    case english = "en"         // English
    case zhHans = "zh-Hans"     // 简体中文 (Mandarin)
    case zhHant = "zh-Hant"     // 繁體中文
    case korean = "ko"          // 한국어 (Korean)
    case arabic = "ar"          // العربية (Arabic)
    case portuguese = "pt-BR"   // Português (Brasil)
    case spanish = "es"         // Español
    case german = "de"          // Deutsch
    case italian = "it"         // Italiano
    case japanese = "ja"        // 日本語 (Japanese)
    case russian = "ru"         // Русский
    case turkish = "tr"         // Türkçe
    case dutch = "nl"           // Nederlands
    case polish = "pl"          // Polski
    case hindi = "hi"           // हिन्दी (Hindi)
    case vietnamese = "vi"      // Tiếng Việt
    case ukrainian = "uk"       // Українська

    public var id: String { rawValue }

    public init?(rawValue: String) {
        switch rawValue {
        case "fr": self = .french
        case "en": self = .english
        case "zh-Hans": self = .zhHans
        case "zh-Hant": self = .zhHant
        case "ko": self = .korean
        case "ar": self = .arabic
        case "pt-BR", "pt": self = .portuguese
        case "es": self = .spanish
        case "de": self = .german
        case "it": self = .italian
        case "ja": self = .japanese
        case "ru": self = .russian
        case "tr": self = .turkish
        case "nl": self = .dutch
        case "pl": self = .polish
        case "hi": self = .hindi
        case "vi": self = .vietnamese
        case "uk": self = .ukrainian
        default: return nil
        }
    }

    public var locale: Locale {
        switch self {
        case .french: return Locale(identifier: "fr_FR")
        case .english: return Locale(identifier: "en_US")
        case .zhHans: return Locale(identifier: "zh_CN")
        case .zhHant: return Locale(identifier: "zh_TW")
        case .korean: return Locale(identifier: "ko_KR")
        case .arabic: return Locale(identifier: "ar_SA")
        case .portuguese: return Locale(identifier: "pt_BR")
        case .spanish: return Locale(identifier: "es_ES")
        case .german: return Locale(identifier: "de_DE")
        case .italian: return Locale(identifier: "it_IT")
        case .japanese: return Locale(identifier: "ja_JP")
        case .russian: return Locale(identifier: "ru_RU")
        case .turkish: return Locale(identifier: "tr_TR")
        case .dutch: return Locale(identifier: "nl_NL")
        case .polish: return Locale(identifier: "pl_PL")
        case .hindi: return Locale(identifier: "hi_IN")
        case .vietnamese: return Locale(identifier: "vi_VN")
        case .ukrainian: return Locale(identifier: "uk_UA")
        }
    }

    public var flag: String {
        switch self {
        case .french: return "🇫🇷"
        case .english: return "🇬🇧"
        case .zhHans: return "🇨🇳"
        case .zhHant: return "🇹🇼"
        case .korean: return "🇰🇷"
        case .arabic: return "🇸🇦"
        case .portuguese: return "🇧🇷"
        case .spanish: return "🇪🇸"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .japanese: return "🇯🇵"
        case .russian: return "🇷🇺"
        case .turkish: return "🇹🇷"
        case .dutch: return "🇳🇱"
        case .polish: return "🇵🇱"
        case .hindi: return "🇮🇳"
        case .vietnamese: return "🇻🇳"
        case .ukrainian: return "🇺🇦"
        }
    }

    /// Name of the language, written in that language.
    public var nativeName: String {
        switch self {
        case .french: return "Français"
        case .english: return "English"
        case .zhHans: return "简体中文 (Mandarin)"
        case .zhHant: return "繁體中文"
        case .korean: return "한국어 (Korean)"
        case .arabic: return "العربية (Arabic)"
        case .portuguese: return "Português (Brasil)"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .japanese: return "日本語 (Japanese)"
        case .russian: return "Русский"
        case .turkish: return "Türkçe"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .hindi: return "हिन्दी (Hindi)"
        case .vietnamese: return "Tiếng Việt"
        case .ukrainian: return "Українська"
        }
    }

    public var displayName: String {
        "\(flag)  \(nativeName)"
    }

    public var isRTL: Bool {
        self == .arabic
    }

    public static func matchPreferred(_ languages: [String]) -> AppLanguage {
        for lang in languages {
            let lower = lang.lowercased()
            if lower.starts(with: "fr") { return .french }
            if lower.starts(with: "en") { return .english }
            if lower.starts(with: "zh-hans") || lower.starts(with: "zh-cn") || lower.starts(with: "zh-sg") { return .zhHans }
            if lower.starts(with: "zh") { return .zhHant }
            if lower.starts(with: "ko") { return .korean }
            if lower.starts(with: "ar") { return .arabic }
            if lower.starts(with: "pt") { return .portuguese }
            if lower.starts(with: "es") { return .spanish }
            if lower.starts(with: "de") { return .german }
            if lower.starts(with: "it") { return .italian }
            if lower.starts(with: "ja") { return .japanese }
            if lower.starts(with: "ru") { return .russian }
            if lower.starts(with: "tr") { return .turkish }
            if lower.starts(with: "nl") { return .dutch }
            if lower.starts(with: "pl") { return .polish }
            if lower.starts(with: "hi") { return .hindi }
            if lower.starts(with: "vi") { return .vietnamese }
            if lower.starts(with: "uk") { return .ukrainian }
        }
        return .french
    }
}

/// The language is read once at launch or dynamically updated when selected in Settings.
public enum Localization {
    public static let defaultsKey = "appLanguage"

    public static var language: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        return AppLanguage.matchPreferred(Locale.preferredLanguages)
    }() {
        didSet {
            Formatters.locale = language.locale
        }
    }

    public static var isFrench: Bool { language == .french }
    public static var isEnglish: Bool { language == .english }

    // Fast reverse lookup table built once: English or French string -> StringKey
    private static let keyMap: [String: StringKey] = {
        var map = [String: StringKey]()
        for (key, val) in Translations.english {
            map[val] = key
            map[val.lowercased()] = key
        }
        for (key, val) in Translations.french {
            map[val] = key
            map[val.lowercased()] = key
        }
        return map
    }()

    /// Host-app translations consulted first for languages other than English and French
    /// (Aman Check registers its own tables here; Aman Disk leaves it nil).
    public static var extraLookup: ((_ english: String, _ french: String, _ language: AppLanguage) -> String?)?

    public static func translate(english: String, french: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return english
        case .french:
            return french
        default:
            // 0. Host-app tables (Aman Check)
            if let extra = extraLookup?(english, french, language) {
                return extra
            }
            // 1. Exact match via StringKey dictionary
            if let key = keyMap[english] ?? keyMap[french] ?? keyMap[english.lowercased()] ?? keyMap[french.lowercased()] {
                let dict = Translations.dictionary(for: language)
                if let val = dict[key], !val.isEmpty {
                    return val
                }
            }
            // 2. Extra translations for attributes, alerts, and settings
            if let extra = ExtraTranslations.lookup(english: english, french: french, language: language) {
                return extra
            }
            return english
        }
    }
}

/// Picks the text for the current language: `L("Read", "Lecture")`.
public func L(_ english: String, _ french: String) -> String {
    Localization.translate(english: english, french: french, language: Localization.language)
}

/// Picks the text for a typed StringKey: `L(.appName)`.
public func L(_ key: StringKey) -> String {
    let dict = Translations.dictionary(for: Localization.language)
    if let val = dict[key], !val.isEmpty {
        return val
    }
    if Localization.isFrench, let fr = Translations.french[key] {
        return fr
    }
    if let en = Translations.english[key] {
        return en
    }
    return key.rawValue
}
