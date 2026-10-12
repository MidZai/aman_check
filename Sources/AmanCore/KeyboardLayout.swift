import Foundation

/// Type physique du clavier (forme de la touche Entrée, touche en plus à côté de Maj gauche).
public enum PhysicalKeyboard: String, Codable, Sendable, CaseIterable {
    case ansi, iso

    public var label: String {
        switch self {
        case .ansi: return "ANSI"
        case .iso: return "ISO"
        }
    }
}

/// Rangée du haut d'un portable.
public enum KeyboardTopRow: String, Codable, Sendable {
    case functionKeys   // vraie rangée F1–F12
    case touchBar       // Échap + Touch Bar
}

/// Une touche physique, identifiée par son `keyCode` (constantes `kVK_*` de Carbon),
/// jamais par le caractère produit : le test marche en AZERTY, QWERTY, arabe…
public struct KeyboardKey: Hashable, Sendable, Identifiable {
    public var id: UInt16 { code }
    public let code: UInt16
    /// Libellé par défaut (QWERTY / symbole). L'app remplace les touches de caractère
    /// par le caractère de la disposition active (UCKeyTranslate).
    public let label: String
    public let isCharacter: Bool
    /// Touche de modificateur : reçue en `.flagsChanged`, pas en `.keyDown`.
    public let isModifier: Bool
    /// Rangée F1–F12 : sans fn, macOS envoie une touche média (`NX_KEYTYPE_*`) au lieu de la touche F.
    public let mediaKeyTypes: [Int]
    /// Autres keyCodes possibles pour la même touche physique.
    public let alternateCodes: [UInt16]
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
}

/// Élément dessiné mais non testé (Touch Bar, Touch ID).
public struct KeyboardDecoration: Hashable, Sendable {
    public enum Kind: String, Sendable { case touchBar, touchID }
    public let kind: Kind
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
}

/// Modèle de clavier piloté par des données (correctifs §6.2). Unités : largeur d'une touche = 1.
public struct KeyboardLayout: Sendable {
    public let physical: PhysicalKeyboard
    public let topRow: KeyboardTopRow
    public let keys: [KeyboardKey]
    public let decorations: [KeyboardDecoration]
    public let width: Double
    public let height: Double

    /// Le total « X / N » vient du modèle, jamais d'un nombre fixe.
    public var keyCount: Int { keys.count }

    /// Touche correspondant à un keyCode reçu (y compris les codes alternatifs).
    public func key(forCode code: UInt16) -> KeyboardKey? {
        keys.first { $0.code == code || $0.alternateCodes.contains(code) }
    }

    /// Touche de la rangée F1–F12 correspondant à une touche média reçue sans fn.
    public func key(forMediaKeyType type: Int) -> KeyboardKey? {
        keys.first { $0.mediaKeyTypes.contains(type) }
    }

    // MARK: - Constructeur

    static let rowGap = 0.14
    static let keyGap = 0.14
    static let rowWidth = 14.5

    /// Clavier de MacBook (Air ou Pro, 2018 et plus).
    public static func macBook(physical: PhysicalKeyboard, topRow: KeyboardTopRow) -> KeyboardLayout {
        var keys: [KeyboardKey] = []
        var decorations: [KeyboardDecoration] = []
        var y = 0.0
        var x = 0.0

        func add(_ code: UInt16, _ label: String, w: Double = 1, h: Double = 1, char: Bool = false, modifier: Bool = false,
                 media: [Int] = [], alt: [UInt16] = [], atX: Double? = nil, atY: Double? = nil) {
            keys.append(KeyboardKey(code: code, label: label, isCharacter: char, isModifier: modifier,
                                    mediaKeyTypes: media, alternateCodes: alt,
                                    x: atX ?? x, y: atY ?? y, w: w, h: h))
            if atX == nil { x += w }
        }
        func nextRow(height: Double) {
            y += height + rowGap
            x = 0
        }

        // Rangée du haut (demi-hauteur).
        let topHeight = 0.6
        switch topRow {
        case .functionKeys:
            add(53, "esc", w: 1.5, h: topHeight)
            // keyCodes F1–F12 (kVK_F1…kVK_F12) et touches média envoyées sans fn (NX_KEYTYPE_*).
            // TODO: à valider sur machine réelle avec rangée physique (F3/F4 : Mission Control 160, Launchpad 131).
            let fKeys: [(UInt16, String, [Int], [UInt16])] = [
                (122, "F1", [3], []), (120, "F2", [2], []), (99, "F3", [], [160]), (118, "F4", [], [131]),
                (96, "F5", [22], []), (97, "F6", [21], []), (98, "F7", [18, 20], []), (100, "F8", [16], []),
                (101, "F9", [17, 19], []), (109, "F10", [7], []), (103, "F11", [1], []), (111, "F12", [0], [])
            ]
            for (code, label, media, alt) in fKeys {
                add(code, label, w: 1, h: topHeight, media: media, alt: alt)
            }
            decorations.append(KeyboardDecoration(kind: .touchID, x: x, y: y, w: 1, h: topHeight))
        case .touchBar:
            add(53, "esc", w: 1, h: topHeight)
            decorations.append(KeyboardDecoration(kind: .touchBar, x: x, y: y, w: rowWidth - 2, h: topHeight))
            decorations.append(KeyboardDecoration(kind: .touchID, x: rowWidth - 1, y: y, w: 1, h: topHeight))
        }
        nextRow(height: topHeight)

        // Rangée des chiffres. ISO : touche « § / @ » = kVK_ISO_Section (10) ; ANSI : « ` » = kVK_ANSI_Grave (50).
        if physical == .iso { add(10, "§", char: true) } else { add(50, "`", char: true) }
        for (code, label) in [(18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"),
                              (28, "8"), (25, "9"), (29, "0"), (27, "-"), (24, "=")] as [(UInt16, String)] {
            add(code, label, char: true)
        }
        add(51, "⌫", w: 1.5)
        nextRow(height: 1)

        // Rangée QWERTY.
        add(48, "⇥", w: 1.5)
        for (code, label) in [(12, "Q"), (13, "W"), (14, "E"), (15, "R"), (17, "T"), (16, "Y"), (32, "U"),
                              (34, "I"), (31, "O"), (35, "P"), (33, "["), (30, "]")] as [(UInt16, String)] {
            add(code, label, char: true)
        }
        if physical == .ansi {
            add(42, "\\", w: 1, char: true)
        } else {
            // Entrée ISO : sur deux rangées.
            add(36, "↩", w: 1, h: 2 + rowGap)
        }
        nextRow(height: 1)

        // Rangée ASDF.
        add(57, "⇪", w: physical == .ansi ? 1.75 : 1.5)
        for (code, label) in [(0, "A"), (1, "S"), (2, "D"), (3, "F"), (5, "G"), (4, "H"), (38, "J"),
                              (40, "K"), (37, "L"), (41, ";"), (39, "'")] as [(UInt16, String)] {
            add(code, label, char: true)
        }
        if physical == .ansi {
            add(36, "↩", w: 1.75)
        } else {
            add(42, "\\", w: 1, char: true)
        }
        nextRow(height: 1)

        // Rangée ZXCV. ISO : touche en plus à droite de Maj gauche = kVK_ANSI_Grave (50) sur les claviers Apple ISO.
        add(56, "⇧", w: physical == .ansi ? 2.25 : 1.25, modifier: true)
        if physical == .iso { add(50, "<", char: true) }
        for (code, label) in [(6, "Z"), (7, "X"), (8, "C"), (9, "V"), (11, "B"), (45, "N"), (46, "M"),
                              (43, ","), (47, "."), (44, "/")] as [(UInt16, String)] {
            add(code, label, char: true)
        }
        add(60, "⇧", w: 2.25, modifier: true)
        nextRow(height: 1)

        // Rangée du bas : fn, ⌃, ⌥, ⌘, espace, ⌘, ⌥, flèches en T inversé.
        add(63, "fn", modifier: true)
        add(59, "⌃", modifier: true)
        add(58, "⌥", modifier: true)
        add(55, "⌘", w: 1.25, modifier: true)
        add(49, "", w: 5)
        add(54, "⌘", w: 1.25, modifier: true)
        add(61, "⌥", modifier: true)
        let half = (1 - rowGap / 2) / 2
        let arrowsX = x
        add(123, "←", w: 1, h: half, atX: arrowsX, atY: y + 1 - half)
        add(126, "↑", w: 1, h: half, atX: arrowsX + 1, atY: y)
        add(125, "↓", w: 1, h: half, atX: arrowsX + 1, atY: y + 1 - half)
        add(124, "→", w: 1, h: half, atX: arrowsX + 2, atY: y + 1 - half)

        return KeyboardLayout(physical: physical, topRow: topRow, keys: keys, decorations: decorations,
                              width: rowWidth, height: y + 1)
    }
}
