import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Parcours « Contrôle » en trois temps : accueil → analyse → résultats (correctifs §4).
struct OverviewView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        switch controller.phase {
        case .welcome: WelcomeView()
        case .analyzing: AnalyzingView()
        case .results: ResultsView()
        }
    }
}

// MARK: - Accueil

private struct WelcomeView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                MachineHero(size: 170)

                VStack(spacing: 18) {
                    Text(L("About 5 minutes. Checks the locks, the battery and the SSD, then guides you through testing the display, the keyboard and the sound.",
                           "Environ 5 minutes. Vérifie les verrouillages, la batterie et le SSD, puis vous guide pour tester l'écran, le clavier et le son."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await controller.runAnalysis() }
                    } label: {
                        Text(L("Run the Check", "Lancer le contrôle"))
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                TrustNotice()
                    .frame(maxWidth: 760)

                HStack(alignment: .top, spacing: AmanDesign.gridSpacing) {
                    Feature(symbol: "lock.shield", title: L("Locks", "Verrouillages"),
                            text: L("iCloud, company management, firmware", "iCloud, gestion d'entreprise, firmware"))
                    Feature(symbol: "battery.75percent", title: L("Battery and SSD", "Batterie et SSD"),
                            text: L("Real wear, read on this Mac", "Usure réelle, lue sur ce Mac"))
                    Feature(symbol: "hand.tap", title: L("Guided tests", "Tests guidés"),
                            text: L("Display, keyboard, trackpad, sound, camera", "Écran, clavier, trackpad, son, caméra"))
                }
                .frame(maxWidth: 760)

                Label(L("Local condition report (level 1): nothing is sent anywhere.",
                        "Rapport d'état local (niveau 1) : rien n'est envoyé."),
                      systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
            }
            .padding(AmanDesign.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }

    private struct Feature: View {
        let symbol: String
        let title: String
        let text: String

        var body: some View {
            AmanCard(padding: AmanDesign.tilePadding) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(AmanPalette.water)
                        .frame(width: 30, height: 28, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(title).font(.headline)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Premier lancement : ce que fait et ne fait pas l'app (retours Reddit, l'avertissement Gatekeeper inquiète).
/// « Compris » le masque pour de bon (préférence locale). Toujours affiché en mode --snapshot.
private struct TrustNotice: View {
    @AppStorage("trustNotice.acknowledged") private var acknowledged = false

    var body: some View {
        if !acknowledged || Snapshots.directory != nil {
            Callout(tint: AmanPalette.water, symbol: "hand.raised") {
                Text(L("What Aman Check does, and doesn't do", "Ce que fait et ne fait pas Aman Check"))
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    line("eye", L("Reads only: nothing is changed on this Mac.", "Lecture seule : rien n'est modifié sur ce Mac."))
                    line("wifi.slash", L("No connection: nothing leaves this Mac.", "Aucune connexion : rien ne quitte ce Mac."))
                    line("person.crop.circle.badge.xmark", L("No password asked, no Apple Account needed.", "Aucun mot de passe demandé, aucun compte Apple nécessaire."))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(L("Got It", "Compris")) { acknowledged = true }
                }
            }
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22).accessibilityHidden(true)
            Text(text)
        }
    }
}

/// Visuel + nom + caractéristiques principales.
private struct MachineHero: View {
    @EnvironmentObject var controller: CheckController
    let size: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            MacVisual(profile: controller.profile, size: size)
            Text(controller.profile.displayName)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
            if !controller.profile.isRecognized {
                StatusPill(.info, text: L("Model not recognized", "Modèle non reconnu"))
            }
            if controller.profile.isSimulated {
                StatusPill(.watch, text: L("Simulated profile", "Profil simulé"))
            }
            Text(controller.preview.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Analyse

private struct AnalyzingView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                MachineHero(size: 130)
                AmanCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("Automatic analysis", "Analyse automatique"))
                            .font(.headline)
                        ForEach(AnalysisStep.allCases) { step in
                            HStack(spacing: 12) {
                                stepIcon(controller.steps[step] ?? .pending)
                                    .frame(width: 20)
                                Text(step.title)
                                    .foregroundStyle(controller.steps[step] == .pending ? .secondary : .primary)
                                Spacer()
                                Text(stepLabel(controller.steps[step] ?? .pending))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: 460)
                Spacer(minLength: 12)
            }
            .padding(AmanDesign.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func stepIcon(_ state: StepState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor)
        }
    }

    private func stepLabel(_ state: StepState) -> String {
        switch state {
        case .pending: return L("Waiting", "En attente")
        case .running: return L("In progress…", "En cours…")
        case .done: return L("Done", "Terminé")
        }
    }
}

// MARK: - Résultats

private struct ResultsView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        let report = controller.report
        let summary = ReportSummary(report: report)
        ScrollView {
            VStack(alignment: .leading, spacing: AmanDesign.sectionSpacing) {
                // Un blocage (Activation Lock, MDM, machine virtuelle) reste toujours en tête, en rouge (spec §4).
                ForEach(summary.blockers) { blocker in
                    Callout(tint: .red, symbol: "lock.trianglebadge.exclamationmark") {
                        Text(blocker.label + L(": ", " : ") + blocker.displayText).font(.headline)
                        if let detail = blocker.detail { Text(detail) }
                        if let note = blocker.note {
                            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Ce que l'acheteur veut voir d'abord : le Mac, ses caractéristiques et ses chiffres clés
                // (batterie, SSD, heures de fonctionnement, données écrites).
                MachineShowcase(report: report)
                KeyFigures()
                // Verrouillages en liste discrète : un verrou actif est de toute façon remonté en rouge en tête de page.
                KeyLocksPanel()

                VerdictBanner(summary: summary)

                AdaptiveRow(minItemWidth: 340) {
                    PointsCard(title: L("Strengths", "Points forts"), symbol: "hand.thumbsup",
                               points: ReportInsights.strengths(report),
                               empty: L("Nothing to highlight yet.", "Rien à mettre en avant pour l'instant."))
                    PointsCard(title: L("To check before buying", "À vérifier avant l'achat"), symbol: "checklist",
                               points: ReportInsights.toCheck(report),
                               empty: L("Nothing left to check.", "Plus rien à vérifier."))
                }

                MetricSectionView(section: .connectivity)
                AdvancedDetails(measurements: controller.measurements)

                Text(ReportText.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AmanDesign.pagePadding)
            .frame(maxWidth: AmanDesign.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Pastille « Niveau 1 · Local » avec l'explication des trois niveaux (spec §2).
struct TrustBadge: View {
    @EnvironmentObject var controller: CheckController
    @EnvironmentObject var publisher: PublishController

    var body: some View {
        // Niveau dérivé : 2 seulement si le rapport courant a été publié (§8).
        let level2 = controller.phase == .results && publisher.level(for: controller.report.reportID) == 2
        HStack(spacing: 6) {
            Label(level2 ? Level2Text.trustLevel2 : L("Level 1 · Local report", "Niveau 1 · Rapport local"),
                  systemImage: level2 ? "checkmark.seal" : "doc.badge.clock")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            InfoButton(ReportText.trustExplanation)
        }
    }
}

/// Compteurs honnêtes, sans note globale (spec §4).
private struct VerdictBanner: View {
    @EnvironmentObject var controller: CheckController
    let summary: ReportSummary

    var body: some View {
        AmanCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { counters; Spacer(minLength: 16); testsBlock }
                VStack(alignment: .leading, spacing: 14) { counters; testsBlock }
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 28) {
            // Pluriel français : 0 et 1 prennent le singulier (« 0 problème », « 1 bon »).
            counter(summary.good, .good, L("good", summary.good > 1 ? "bons" : "bon"))
            counter(summary.watch, .watch, L("to watch", "à surveiller"))
            counter(summary.problem, .problem, L(summary.problem == 1 ? "problem" : "problems", summary.problem > 1 ? "problèmes" : "problème"))
            counter(summary.notTested, .notTested, L("not tested", summary.notTested > 1 ? "non testés" : "non testé"))
            if summary.toCheck > 0 {
                counter(summary.toCheck, .manualRequired, L("to check manually", "à vérifier soi-même"))
            }
        }
    }

    private func counter(_ value: Int, _ status: CheckStatus, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(AmanDesign.valueFont)
                .monospacedDigit()
                .foregroundStyle(value == 0 ? .secondary : .primary)
            Label {
                Text(label)
            } icon: {
                Image(systemName: status.symbolName).foregroundStyle(status.color)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var testsBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(summary.testsText)
                .font(.callout.weight(.medium))
            if summary.testsDone < summary.testsPlanned {
                Button(L("Start Guided Tests", "Lancer les tests guidés")) {
                    controller.selection = .tests
                    controller.wizardStart = controller.plannedTests.first { controller.results[$0] == nil } ?? controller.plannedTests.first
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Verrouillages en liste compacte : une ligne par contrôle (iCloud, compte Apple, MDM, mot de passe firmware).
/// Un verrou actif est déjà remonté en rouge en tête de page (blocage) : ici, pas besoin de grandes tuiles.
/// Une donnée absente n'est jamais verte.
private struct KeyLocksPanel: View {
    @EnvironmentObject var controller: CheckController

    private static let order = [MetricID.activationLock, MetricID.appleAccount, MetricID.mdm, MetricID.firmwarePassword]

    private func symbol(_ id: String) -> String {
        switch id {
        case MetricID.activationLock: return "icloud"
        case MetricID.appleAccount: return "person.crop.circle"
        case MetricID.mdm: return "building.2"
        default: return "key"
        }
    }

    var body: some View {
        let rows = Self.order.compactMap { controller.measurement($0) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Locks", "Verrouillages"),
                              subtitle: L("To check before buying a used Mac.", "À vérifier avant d'acheter un Mac d'occasion."))
                AmanCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, m in
                            KeyLockRow(measurement: m, symbol: symbol(m.id))
                            if index < rows.count - 1 { Divider().padding(.vertical, 6) }
                        }
                    }
                }
            }
        }
    }
}

/// Ligne d'un verrouillage : libellé, verdict, puis détail et consigne en petit (jamais tronqués :
/// c'est la consigne que l'utilisateur doit suivre).
private struct KeyLockRow: View {
    let measurement: Measurement
    let symbol: String

    var body: some View {
        let info = MetricCatalog.info(for: measurement.id)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                Text(measurement.label).font(.body.weight(.medium))
                StatusLabel(measurement.status, text: measurement.displayText)
                    .foregroundStyle(measurement.status.isJudgement ? measurement.status.color : Color.secondary)
                Spacer(minLength: 0)
                if let help = info.help { InfoButton(help) }
            }
            if let detail = measurement.detail {
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
            if let note = measurement.note {
                Text(note).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PointsCard: View {
    let title: String
    let symbol: String
    let points: [ReportPoint]
    let empty: String

    var body: some View {
        AmanCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol).font(.headline)
                if points.isEmpty {
                    Text(empty).foregroundStyle(.secondary)
                }
                ForEach(points) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: point.status.symbolName)
                            .foregroundStyle(point.status.color)
                            .frame(width: 16)
                            .accessibilityLabel(point.status.label)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = point.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Tuiles « Essentiel » d'une section (batterie, stockage, sans-fil), façon Aman Disk.
/// Section absente si elle ne contient rien (ex. batterie sur Mac de bureau).
private struct MetricSectionView: View {
    @EnvironmentObject var controller: CheckController
    let section: MetricSection

    var body: some View {
        let items = controller.measurements(in: section, level: .essential)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(section.title)
                AdaptiveRow(minItemWidth: 200) {
                    ForEach(items) { m in
                        let info = MetricCatalog.info(for: m.id)
                        StatTile(label: m.label,
                                 value: m.value == nil ? nil : m.displayText,
                                 detail: m.detail ?? (m.status == .manualRequired ? m.note : nil),
                                 status: info.isJudged ? m.status : nil,
                                 help: info.help,
                                 unavailableText: m.note ?? m.status.label)
                    }
                }
            }
        }
    }
}

/// Détails techniques repliés : méthode de calcul, clé lue, notes (spec §6.2.8).
struct AdvancedDetails: View {
    let measurements: [Measurement]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MetricSection.allCases, id: \.self) { section in
                    let items = measurements.filter { MetricCatalog.info(for: $0.id).section == section }
                    if !items.isEmpty {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, m in
                            AdvancedRow(measurement: m)
                                .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(L("Advanced details", "Détails avancés")).font(AmanDesign.sectionFont)
        }
    }
}

private struct AdvancedRow: View {
    let measurement: Measurement

    var body: some View {
        let info = MetricCatalog.info(for: measurement.id)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(measurement.label)
                .frame(width: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if info.isJudged || measurement.status == .manualRequired || measurement.value == nil {
                        Image(systemName: measurement.status.symbolName)
                            .foregroundStyle(measurement.status.color)
                            .help(measurement.status.label)
                    }
                    Text(measurement.displayText).fontWeight(.medium)
                }
                if let note = measurement.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let method = measurement.method {
                Text(method)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Grille adaptative à hauteurs égales par rangée : autant de colonnes que la largeur le permet
/// (comme StatTilesGrid d'Aman Disk), et des cartes alignées au pixel près.
struct AdaptiveRow<Content: View>: View {
    let minItemWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        EqualHeightGrid(minItemWidth: minItemWidth, spacing: AmanDesign.gridSpacing) { content }
    }
}

struct EqualHeightGrid: Layout {
    let minItemWidth: CGFloat
    let spacing: CGFloat

    private func columns(for width: CGFloat, count: Int) -> Int {
        guard width.isFinite, width > 0 else { return max(1, count) }
        return max(1, min(count, Int((width + spacing) / (minItemWidth + spacing))))
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (cols: Int, itemWidth: CGFloat, heights: [CGFloat]) {
        let cols = columns(for: width, count: subviews.count)
        let itemWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: cols) {
            let row = subviews[start..<min(start + cols, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }.max() ?? 0)
        }
        return (cols, itemWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (minItemWidth * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1)))
        let (_, _, heights) = rows(subviews, width: width)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (cols, itemWidth, heights) = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for (rowIndex, height) in heights.enumerated() {
            for col in 0..<cols {
                let index = rowIndex * cols + col
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(col) * (itemWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: itemWidth, height: height))
            }
            y += height + spacing
        }
    }
}
