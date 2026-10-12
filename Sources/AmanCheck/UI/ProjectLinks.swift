import SwiftUI
import AppKit
import AmanDesign
import DiskHealthCore

/// Pied de page du volet principal : à gauche le lien vers Aman Disk (pour aller plus loin sur le disque),
/// à droite le bouton Ko-fi, repris de la carte « Soutenir » d'Aman Disk (ContentView.swift, SupportButton).
struct ProjectFooter: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AmanDiskLink()
            Spacer(minLength: 12)
            SupportButton()
        }
        .padding(.horizontal, AmanDesign.pagePadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Bouton « Soutenir · Ko-fi » : même style qu'Aman Disk (cœur rose, fond teinté, flèche au survol), en version compacte.
struct SupportButton: View {
    @State private var isHovered = false

    private static let tint = Color.pink

    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.supportURL)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").accessibilityHidden(true)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Self.tint.gradient, in: Circle())
                    .scaleEffect(isHovered ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Support Aman Check", "Soutenir Aman Check"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L("Free & open source · Ko-fi", "Gratuit et libre · Ko-fi"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Self.tint.opacity(isHovered ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Self.tint.opacity(0.25)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(L("Opens the project's Ko-fi page in your browser", "Ouvre la page Ko-fi du projet dans votre navigateur"))
        .accessibilityLabel(L("Support Aman Check on Ko-fi", "Soutenir Aman Check sur Ko-fi"))
        .onHover { hovering in
            isHovered = hovering
            // set() plutôt que push()/pop() : un survol interrompu ne laisse pas la main figée.
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

/// Petit lien vers Aman Disk (GitHub) : tests approfondis du disque, pour qui veut aller plus loin.
struct AmanDiskLink: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.amanDiskURL)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").accessibilityHidden(true)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmanPalette.water)
                Text(L("Go further on the disk: ", "Pour aller plus loin sur le disque : "))
                    .foregroundStyle(.secondary)
                + Text("Aman Disk")
                    .foregroundStyle(isHovered ? AmanPalette.water : .primary)
                    .fontWeight(.semibold)
                + Text(L(" · free & open source", " · gratuit et open source"))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .font(.caption)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(L("Aman Disk checks the health and speed of a disk in depth (S.M.A.R.T., benchmarks). Opens GitHub in your browser.",
                "Aman Disk vérifie en profondeur la santé et la vitesse d'un disque (S.M.A.R.T., tests de vitesse). Ouvre GitHub dans votre navigateur."))
        .accessibilityLabel(L("Aman Disk on GitHub", "Aman Disk sur GitHub"))
        .onHover { hovering in
            isHovered = hovering
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}
