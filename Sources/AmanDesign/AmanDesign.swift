import SwiftUI
import AppKit
import AmanCore
import DiskHealthCore

/// Jetons de design repris d'Aman Disk (DiskHealthApp, v1.0.0). Aman Disk s'appuie sur les couleurs
/// et polices du système (thème clair/sombre automatique) ; seules les couleurs de l'anneau sont propres
/// à la marque. Valeurs relevées dans : StatTile.swift, AmanRing.swift, HealthRingView.swift,
/// HealthStatus+Color.swift, DiskDetailView.swift, SmartTableView.swift, ContentView.swift, ReportPageView.swift.
public enum AmanDesign {
    // Rayons
    public static let cardRadius: CGFloat = 12          // StatTile, SmartTableView, ReasonsCallout
    public static let innerRadius: CGFloat = 8           // tableau S.M.A.R.T., bandeau du PDF
    // Marges
    public static let pagePadding: CGFloat = 24          // DiskDetailView
    public static let sectionSpacing: CGFloat = 24       // DiskDetailView
    public static let tilePadding: CGFloat = 14          // StatTile
    public static let cardPadding: CGFloat = 16          // SmartTableView
    public static let gridSpacing: CGFloat = 12          // StatTilesGrid
    public static let maxContentWidth: CGFloat = 1200    // DiskDetailView
    // Barre latérale (ContentView : navigationSplitViewColumnWidth)
    public static let sidebarMin: CGFloat = 220
    public static let sidebarIdeal: CGFloat = 250
    public static let sidebarMax: CGFloat = 320
    // Fenêtre (DiskHealthApp)
    public static let windowMinWidth: CGFloat = 960
    public static let windowMinHeight: CGFloat = 640
    public static let windowDefaultWidth: CGFloat = 1280
    public static let windowDefaultHeight: CGFloat = 860

    /// Fond des cartes : `controlBackgroundColor`, comme StatTile.
    public static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    /// Bordure subtile des cartes.
    public static var cardBorder: Color { Color.secondary.opacity(0.15) }

    /// Grande valeur d'une tuile (StatTile).
    public static let valueFont = Font.system(size: 24, weight: .semibold, design: .rounded)
    /// Titre de section (TemperatureHistoryView).
    public static let sectionFont = Font.title3.bold()
}

/// Couleurs de la marque, réservées à l'anneau (AmanRing.swift).
public enum AmanPalette {
    public static let water = Color(hex: "#2E9FD6")
    public static let orange = Color(hex: "#E8A33D")
    public static let red = Color(hex: "#E5534B")
    public static let ink = Color(hex: "#0B2230")
}

public extension CheckStatus {
    /// Vert = Bon, orange = À surveiller, rouge = Problème, gris = Non testé / Non disponible,
    /// bleu = Vérification manuelle (correctifs §3.2). Couleurs système, comme Aman Disk.
    var color: Color {
        switch self {
        case .good: return .green
        case .watch: return .orange
        case .problem: return .red
        case .manualRequired: return .blue
        case .notTested, .unavailable, .notApplicable, .info: return .gray
        }
    }
}

public extension Color {
    /// Couleur de marque, en sRGB : « #RRGGBB » ou « #AARRGGBB » (copie d'Aman Disk).
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch digits.count {
        case 6: (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8: (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Conteneurs

/// Carte : fond `controlBackgroundColor`, rayon 12 continu, bordure 15 %.
public struct AmanCard<Content: View>: View {
    var padding: CGFloat
    @ViewBuilder var content: Content

    public init(padding: CGFloat = AmanDesign.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AmanDesign.cardBackground, in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(AmanDesign.cardBorder))
    }
}

/// Encadré teinté (ReasonsCallout / SmartEnabledCard d'Aman Disk).
public struct Callout<Content: View>: View {
    let tint: Color
    let symbol: String
    @ViewBuilder var content: Content

    public init(tint: Color, symbol: String, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.symbol = symbol
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) { content }
            Spacer(minLength: 0)
        }
        .padding(AmanDesign.tilePadding)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(tint.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }
}

/// Titre de section, avec sous-titre optionnel.
public struct SectionHeader: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AmanDesign.sectionFont)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Statuts

/// Icône + libellé coloré : jamais la couleur seule (correctifs §3.2).
public struct StatusLabel: View {
    let status: CheckStatus
    let text: String?
    var font: Font = .callout.weight(.medium)

    public init(_ status: CheckStatus, text: String? = nil, font: Font = .callout.weight(.medium)) {
        self.status = status
        self.text = text
        self.font = font
    }

    public var body: some View {
        Label {
            Text(text ?? status.label)
        } icon: {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
        }
        .font(font)
    }
}

/// Pastille compacte : fond teinté, icône et texte.
public struct StatusPill: View {
    let status: CheckStatus
    let text: String?

    public init(_ status: CheckStatus, text: String? = nil) {
        self.status = status
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName).accessibilityHidden(true)
            Text(text ?? status.label).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status == .info ? Color.secondary : status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tuiles

/// Tuile d'indicateur (StatTile d'Aman Disk) : libellé gris, grande valeur, sous-texte humain.
/// Une pastille n'apparaît que si la mesure est un jugement.
public struct StatTile: View {
    let label: String
    let value: String?
    var detail: String?
    var status: CheckStatus?
    var help: String?
    var unavailableText: String

    public init(label: String, value: String?, detail: String? = nil, status: CheckStatus? = nil, help: String? = nil,
                unavailableText: String = "—") {
        self.label = label
        self.value = value
        self.detail = detail
        self.status = status
        self.help = help
        self.unavailableText = unavailableText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let help { InfoButton(help).font(.caption) }
                Spacer(minLength: 4)
                if let status, status.isJudgement || status == .manualRequired {
                    Image(systemName: status.symbolName)
                        .foregroundStyle(status.color)
                        .font(.subheadline)
                        .help(status.label)
                        .accessibilityLabel(status.label)
                }
            }
            Text(value ?? "—")
                .font(AmanDesign.valueFont)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value == nil ? unavailableText : (detail ?? " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AmanDesign.tilePadding)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .topLeading)
        .background(AmanDesign.cardBackground, in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(AmanDesign.cardBorder))
        .accessibilityElement(children: .contain)
    }
}

/// Paire libellé / valeur (InfoPair d'Aman Disk).
public struct InfoPair: View {
    let label: String
    let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
        }
    }
}

/// Bouton « i » qui ouvre une bulle d'aide.
public struct InfoButton: View {
    let text: String
    @State private var isShown = false

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("More information", "Plus d'informations"))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
    }
}

/// N° de série masqué, partout de la même façon : « ••••1234 » (SerialMasking d'Aman Disk).
public enum SerialMasking {
    public static func masked(_ serial: String?) -> String {
        guard let serial, !serial.isEmpty else { return "—" }
        guard serial.count > 4 else { return "••••" }
        return "••••\(serial.suffix(4))"
    }
}

// MARK: - Animations de symboles

/// Effets de symboles SF (macOS 14) ; sous macOS 13, le symbole reste fixe.
public extension View {
    @ViewBuilder func amanPulse(isActive: Bool) -> some View {
        if #available(macOS 14, *) { symbolEffect(.pulse, isActive: isActive) } else { self }
    }

    @ViewBuilder func amanVariableColor(isActive: Bool) -> some View {
        if #available(macOS 14, *) { symbolEffect(.variableColor.iterative, isActive: isActive) } else { self }
    }
}
