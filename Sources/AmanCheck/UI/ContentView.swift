import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

struct ContentView: View {
    @EnvironmentObject var controller: CheckController
    @EnvironmentObject var publisher: PublishController

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: AmanDesign.sidebarMin, ideal: AmanDesign.sidebarIdeal, max: AmanDesign.sidebarMax)
        } detail: {
            detail
                // En bas à droite : Ko-fi (comme Aman Disk) ; à gauche, le lien vers Aman Disk.
                .safeAreaInset(edge: .bottom, spacing: 0) { ProjectFooter() }
                .toolbar { toolbarContent }
                .navigationTitle(AppInfo.name)
                .navigationSubtitle(controller.profile.displayName)
        }
        // Relancer efface les tests guidés du rapport (nouveau contrôle = nouveau rapport) : on prévient avant.
        .confirmationDialog(L("Run the check again?", "Relancer le contrôle ?"),
                            isPresented: $controller.rerunConfirmationShown, titleVisibility: .visible) {
            Button(L("Run Again and Discard the Tests", "Relancer et effacer les tests"), role: .destructive) {
                Task { await controller.runAnalysis() }
            }
            Button(L("Cancel", "Annuler"), role: .cancel) {}
        } message: {
            let n = controller.testsAtRisk
            Text(L("A new check creates a new report: the \(n) guided test(s) already done will have to be redone.",
                   "Un nouveau contrôle crée un nouveau rapport : \(n) test\(n > 1 ? "s" : "") guidé\(n > 1 ? "s" : "") déjà réalisé\(n > 1 ? "s" : "") devra\(n > 1 ? "ont" : "") être refait\(n > 1 ? "s" : "")."))
        }
        .sheet(item: $controller.wizardStart) { start in
            TestWizard(start: start)
                .environmentObject(controller)
                .environmentObject(publisher)
        }
        .sheet(item: $controller.singleTest) { test in
            TestSheet(test: test)
                .environmentObject(controller)
                .environmentObject(publisher)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch controller.selection ?? .overview {
        case .overview: OverviewView()
        case .tests: TestsView()
        case .performance: PerformanceView(runner: controller.performanceRunner)
        case .report: ReportScreen()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                controller.requestRerun()
            } label: {
                if controller.phase == .analyzing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("Run Again", "Relancer"), systemImage: "arrow.clockwise")
                }
            }
            .help(L("Run the automatic check again (⌘R)", "Relancer l'analyse automatique (⌘R)"))
            .disabled(controller.phase == .analyzing)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(L("Export Report as PDF…", "Exporter le rapport en PDF…")) {
                    publisher.exportPDF(controller.report)
                }
                Button(L("Export Report as JSON…", "Exporter le rapport en JSON…")) {
                    ReportExporter.exportJSON(controller.report)
                }
                Divider()
                Button(L("Export Diagnostic Data…", "Exporter les données de diagnostic…")) {
                    ReportExporter.exportDiagnostic(controller.report)
                }
            } label: {
                Label(L("Export", "Exporter"), systemImage: "square.and.arrow.up")
            }
            .disabled(controller.phase != .results)
            .help(L("Export the condition report", "Exporter le rapport d'état"))
        }
    }
}

// MARK: - Barre latérale

private struct SidebarView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        List(selection: $controller.selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    SidebarRow(item: item)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            MachineCard()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var controller: CheckController
    let item: SidebarItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            badge
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var badge: some View {
        switch item {
        case .overview:
            if controller.phase == .analyzing {
                ProgressView().controlSize(.mini)
            } else if controller.phase == .results {
                let s = controller.summary
                if s.problem > 0 {
                    Circle().fill(Color.red).frame(width: 8, height: 8).help(CheckStatus.problem.label)
                } else if s.watch > 0 {
                    Circle().fill(Color.orange).frame(width: 8, height: 8).help(CheckStatus.watch.label)
                }
            }
        case .tests:
            let done = controller.plannedTests.filter { r in
                controller.results[r].map { $0.outcome == .passed || $0.outcome == .failed } ?? false
            }.count
            Text("\(done)/\(controller.plannedTests.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .performance, .report:
            EmptyView()
        }
    }
}

/// Le Mac contrôlé, en bas de la barre latérale (à la place de la carte « Soutenir » d'Aman Disk).
private struct MachineCard: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        HStack(spacing: 10) {
            MacVisual(profile: controller.profile, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.profile.model.map { "\($0.family) \($0.inches.map { "\($0)″" } ?? "")" } ?? controller.profile.modelIdentifier)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(controller.profile.isSimulated ? L("Simulated profile", "Profil simulé") : (controller.profile.model?.yearText ?? controller.profile.modelIdentifier))
                    .font(.caption)
                    .foregroundStyle(controller.profile.isSimulated ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Visuel du Mac (correctifs §3.5) : icône du modèle fournie par macOS à l'exécution
/// (celle d'« À propos de ce Mac », jamais redistribuée dans l'app), sinon SF Symbol.
struct MacVisual: View {
    let profile: DeviceProfile
    var size: CGFloat

    var body: some View {
        Group {
            if !profile.isSimulated, let image = NSImage(named: NSImage.computerName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: profile.kind.symbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .fontWeight(.thin)
                    .foregroundStyle(AmanPalette.water)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
