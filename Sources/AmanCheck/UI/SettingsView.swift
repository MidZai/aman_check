import SwiftUI
import AppKit
import DiskHealthCore

/// Réglages (⌘,) : la langue de l'interface, comme dans Aman Disk (SettingsView.swift).
/// Le changement prend effet au redémarrage : les textes sont lus par `L()` à la construction des vues.
struct SettingsView: View {
    @AppStorage(Localization.defaultsKey) private var language = Localization.language.rawValue
    @AppStorage(ReportPage.offlineQRDefaultsKey) private var offlineQR = true

    var body: some View {
        Form {
            Section(L("General", "Général")) {
                Picker(L("Language", "Langue"), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                if language != Localization.language.rawValue {
                    HStack {
                        Text(L("Takes effect after relaunching Aman Check.", "Prend effet au redémarrage d'Aman Check."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Relaunch Now", "Redémarrer maintenant"), action: Self.relaunch)
                    }
                }
                Text(L("You can also change the app language in System Settings › General › Language & Region › Applications.",
                       "Vous pouvez aussi changer la langue de l'application dans Réglages Système › Général › Langue et région › Applications."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section(L("Report", "Rapport")) {
                Toggle(L("Summary QR code in the PDF", "QR code de résumé dans le PDF"), isOn: $offlineQR)
                Text(L("A QR code on the first page holds a short text summary of the report (no link, nothing sent). It does not prove that the report is authentic.",
                       "Un QR code sur la première page contient un court résumé texte du rapport (aucun lien, rien n'est envoyé). Il ne prouve pas l'authenticité du rapport."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Relance l'app (nouvelle instance) puis quitte celle-ci ; hors d'un .app (swift run), ne fait rien.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
