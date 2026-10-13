import Foundation
import DiskHealthCore

/// Traductions propres à Aman Check pour les 16 langues autres que l'anglais et le français
/// (les textes anglais et français sont écrits dans le code : `L("English", "Français")`).
///
/// Les tables `AmanTranslations_XX.swift` sont GÉNÉRÉES par `scripts/gen_translations.py` à partir de
/// `scripts/translations/<langue>.json` : ne pas les modifier à la main. Clé = texte anglais.
/// Les valeurs insérées (`\(expr)`) sont représentées par `{0}`, `{1}`… dans l'ordre du texte anglais ;
/// la traduction peut les réordonner. `scripts/extract_strings.py --missing` liste ce qui manque.
enum AmanTranslations {
    /// À appeler au lancement : branche les tables sur `L()` (DiskHealthCore).
    static func install() {
        Localization.extraLookup = lookup
    }

    static func table(for language: AppLanguage) -> [String: String]? {
        switch language {
        case .english, .french: return nil
        case .zhHans: return zhHans
        case .zhHant: return zhHant
        case .korean: return korean
        case .arabic: return arabic
        case .portuguese: return portuguese
        case .spanish: return spanish
        case .german: return german
        case .italian: return italian
        case .japanese: return japanese
        case .russian: return russian
        case .turkish: return turkish
        case .dutch: return dutch
        case .polish: return polish
        case .hindi: return hindi
        case .vietnamese: return vietnamese
        case .ukrainian: return ukrainian
        }
    }

    static func lookup(english: String, french: String, language: AppLanguage) -> String? {
        guard let table = table(for: language) else { return nil }
        if let exact = table[english] { return exact }
        return templates(for: language).translate(english)
    }

    // MARK: - Modèles avec valeurs insérées

    /// Un texte anglais contenant des valeurs (`Step {0} of {1}`) arrive dans `L()` déjà rempli
    /// (`Step 2 of 5`) : on retrouve le modèle par expression régulière et on réinjecte les valeurs
    /// dans la traduction. Les résultats sont mis en cache (les collecteurs appellent `L()` hors du fil principal).
    final class Templates: @unchecked Sendable {
        private struct Template {
            let regex: NSRegularExpression
            let translation: String
            let count: Int
        }

        private let entries: [Template]
        private var cache: [String: String?] = [:]
        private let lock = NSLock()

        init(table: [String: String]) {
            var entries: [Template] = []
            for (english, translation) in table where english.contains("{0}") {
                let parts = Self.split(english)
                // (.*?) : une valeur insérée peut être vide (« 0 problem » : le « s » du pluriel manque).
                let pattern = "^" + parts.literals.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.*?)") + "$"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
                entries.append(Template(regex: regex, translation: translation, count: parts.count))
            }
            // Les modèles les plus longs d'abord : « {0} of {1} USB-C ports tested » avant « {0} tested ».
            self.entries = entries.sorted { $0.regex.pattern.count > $1.regex.pattern.count }
        }

        func translate(_ english: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            if let cached = cache[english] { return cached }
            let result = match(english)
            if cache.count > 2000 { cache.removeAll() }
            cache[english] = result
            return result
        }

        private func match(_ english: String) -> String? {
            let range = NSRange(english.startIndex..., in: english)
            for entry in entries {
                guard let m = entry.regex.firstMatch(in: english, options: [], range: range) else { continue }
                var out = entry.translation
                for i in 0..<entry.count {
                    guard let r = Range(m.range(at: i + 1), in: english) else { continue }
                    out = out.replacingOccurrences(of: "{\(i)}", with: String(english[r]))
                }
                return out
            }
            return nil
        }

        /// « Step {0} of {1} » → littéraux ["Step ", " of ", ""], 2 valeurs.
        private static func split(_ template: String) -> (literals: [String], count: Int) {
            var literals: [String] = []
            var count = 0
            var current = ""
            var rest = Substring(template)
            while let open = rest.firstIndex(of: "{") {
                let afterOpen = rest.index(after: open)
                if let close = rest[afterOpen...].firstIndex(of: "}"), Int(rest[afterOpen..<close]) != nil {
                    current += rest[..<open]
                    literals.append(current)
                    current = ""
                    count += 1
                    rest = rest[rest.index(after: close)...]
                } else {
                    current += rest[...open]
                    rest = rest[afterOpen...]
                }
            }
            current += rest
            literals.append(current)
            return (literals, count)
        }
    }

    private static let templatesLock = NSLock()
    nonisolated(unsafe) private static var templatesByLanguage: [AppLanguage: Templates] = [:]

    static func templates(for language: AppLanguage) -> Templates {
        templatesLock.lock(); defer { templatesLock.unlock() }
        if let t = templatesByLanguage[language] { return t }
        let t = Templates(table: table(for: language) ?? [:])
        templatesByLanguage[language] = t
        return t
    }
}
