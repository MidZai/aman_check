import Foundation

public struct Translations {
    public static func dictionary(for language: AppLanguage) -> [StringKey: String] {
        switch language {
        case .french:
            return french
        case .english:
            return english
        case .zhHans:
            return chineseSimplified
        case .zhHant:
            return chineseTraditional
        case .korean:
            return korean
        case .arabic:
            return arabic
        case .portuguese:
            return portuguese
        case .spanish:
            return spanish
        case .german:
            return german
        case .italian:
            return italian
        case .japanese:
            return japanese
        case .russian:
            return russian
        case .turkish:
            return turkish
        case .dutch:
            return dutch
        case .polish:
            return polish
        case .hindi:
            return hindi
        case .vietnamese:
            return vietnamese
        case .ukrainian:
            return ukrainian
        }
    }
}
