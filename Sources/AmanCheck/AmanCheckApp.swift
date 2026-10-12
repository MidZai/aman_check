import SwiftUI
import AppKit
import AmanDesign
import DiskHealthCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// En mode --snapshot, les fenêtres hors écran se ferment une à une : l'app quitte d'elle-même à la fin.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { Snapshots.directory == nil }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lancé hors d'un .app (swift run) : l'app doit tout de même apparaître au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Mode --snapshot : rendu hors écran, sans dépendre de l'ouverture de la fenêtre principale.
        MainActor.assumeIsolated {
            Snapshots.runIfRequested(AppModels.controller, publisher: AppModels.publisher)
        }
    }
}

/// Modèles de l'app, créés une fois (partagés avec le mode --snapshot).
@MainActor
enum AppModels {
    static let controller = CheckController()
    static let publisher = PublishController()
}

@main
struct AmanCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = AppModels.controller
    @StateObject private var publisher = AppModels.publisher

    init() {
        // Avant toute vue : les 16 langues au-delà de l'anglais et du français, et le choix
        // `--language xx` (captures d'écran : `--snapshot <dossier> --language ar`).
        AmanTranslations.install()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--language"), i + 1 < args.count, let lang = AppLanguage(rawValue: args[i + 1]) {
            Localization.language = lang
        }
    }

    var body: some Scene {
        // Même configuration de fenêtre qu'Aman Disk (DiskHealthApp.swift) : barre d'outils unifiée
        // avec titre, barre latérale native. Pas de `.hiddenTitleBar` (le contenu chevauchait les boutons).
        Window(AppInfo.name, id: "main") {
            ContentView()
                .environmentObject(controller)
                .environmentObject(publisher)
                .environment(\.layoutDirection, Localization.language.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, Localization.language.locale)
                .frame(minWidth: AmanDesign.windowMinWidth, minHeight: AmanDesign.windowMinHeight)
        }
        .defaultSize(width: AmanDesign.windowDefaultWidth, height: AmanDesign.windowDefaultHeight)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("Check", "Contrôle")) {
                Button(L("Run the Check", "Lancer le contrôle")) {
                    controller.requestRerun()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button(L("Start Guided Tests", "Lancer les tests guidés")) {
                    controller.selection = .tests
                    controller.wizardStart = controller.plannedTests.first
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button(L("Export PDF Report…", "Exporter le rapport PDF…")) {
                    publisher.exportPDF(controller.report)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(controller.phase != .results)
                // Niveau 2 : rien n'est envoyé avant la feuille de confirmation.
                Button(L("Publish the Report…", "Publier le rapport…")) {
                    controller.selection = .report
                    publisher.resetError()
                    publisher.showSheet = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(controller.phase != .results || controller.profile.isSimulated)
                Button(L("Export Diagnostic Data…", "Exporter les données de diagnostic…")) {
                    ReportExporter.exportDiagnostic(controller.report)
                }
            }
            // Menu Aide, comme Aman Disk : soutien du projet et lien vers l'outil frère.
            CommandGroup(after: .help) {
                Button(L("Support Aman Check on Ko-fi…", "Soutenir Aman Check sur Ko-fi…")) {
                    NSWorkspace.shared.open(AppInfo.supportURL)
                }
                Button(L("Aman Check on GitHub (source code)…", "Aman Check sur GitHub (code source)…")) {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                }
                Button(L("Aman Disk on GitHub (in-depth disk tests)…", "Aman Disk sur GitHub (tests approfondis du disque)…")) {
                    NSWorkspace.shared.open(AppInfo.amanDiskURL)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(\.layoutDirection, Localization.language.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, Localization.language.locale)
        }
    }
}
