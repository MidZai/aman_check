import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Page « Tests guidés » : un test = une carte, lancement unitaire ou assistant pas à pas.
struct TestsView: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        let planned = controller.plannedTests
        let done = planned.filter { controller.results[$0].map { $0.outcome == .passed || $0.outcome == .failed } ?? false }.count
        ScrollView {
            VStack(alignment: .leading, spacing: AmanDesign.sectionSpacing) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Guided tests", "Tests guidés")).font(.title2.bold())
                        Text(L("A few minutes, one test per screen. Each result says whether it was measured by the app or observed by you.",
                               "Quelques minutes, un test par écran. Chaque résultat indique s'il a été mesuré par l'app ou constaté par vous."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(L("\(done) of \(planned.count) done", "\(done) sur \(planned.count) réalisés"))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                        HStack {
                            if !controller.results.isEmpty {
                                Button(L("Reset", "Réinitialiser")) { controller.resetTests() }
                            }
                            Button(done == 0 ? L("Start Guided Tests", "Lancer les tests guidés") : L("Continue", "Continuer")) {
                                controller.wizardStart = planned.first { controller.results[$0] == nil } ?? planned.first
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                }

                ProgressView(value: Double(done), total: Double(max(planned.count, 1)))
                    .tint(AmanPalette.water)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: AmanDesign.gridSpacing, alignment: .top)],
                          alignment: .leading, spacing: AmanDesign.gridSpacing) {
                    ForEach(planned) { test in
                        TestCard(test: test, result: controller.results[test]) {
                            controller.singleTest = test
                        }
                    }
                }

                if controller.profile.kind.isDesktop {
                    Callout(tint: .blue, symbol: "keyboard") {
                        Text(L("Keyboard, mouse and trackpad are accessories on this Mac: they are not tested and not counted in the report.",
                               "Sur ce Mac, clavier, souris et trackpad sont des accessoires : ils ne sont ni testés ni comptés dans le rapport."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(AmanDesign.pagePadding)
            .frame(maxWidth: AmanDesign.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TestCard: View {
    let test: TestID
    let result: TestResult?
    let action: () -> Void

    var body: some View {
        AmanCard(padding: AmanDesign.tilePadding) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: test.symbolName)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AmanPalette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(test.title).font(.headline)
                    Text(test.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if let result {
                            StatusPill(result.status, text: result.status == .notTested ? result.outcome.label : nil)
                            Text(result.provenance.shortLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            StatusPill(.notTested)
                        }
                    }
                    .padding(.top, 2)
                    if let result, result.status != .notTested {
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Button(result == nil ? L("Test", "Tester") : L("Redo", "Refaire"), action: action)
            }
        }
    }
}

// MARK: - Assistant

/// Assistant pas à pas : étape N/M, grande consigne, Ignorer / Suivant (correctifs §4.4).
struct TestWizard: View {
    @EnvironmentObject var controller: CheckController
    @Environment(\.dismiss) private var dismiss
    @State private var current: TestID?
    @State private var finished = false

    init(start: TestID) {
        _current = State(initialValue: start)
    }

    var body: some View {
        let tests = controller.plannedTests
        VStack(spacing: 0) {
            if let current, !finished, let index = tests.firstIndex(of: current) {
                WizardHeader(step: index + 1, count: tests.count, test: current,
                             onSkip: { finish(TestResult.notTested(current, reason: L("Skipped by the user", "Ignoré par l'utilisateur"))) },
                             onQuit: { dismiss() })
                Divider()
                TestHost(test: current, profile: controller.profile) { result in finish(result) }
                    .id(current)
            } else {
                WizardSummary { dismiss() } onReport: {
                    controller.selection = .report
                    dismiss()
                }
            }
        }
        .frame(minWidth: 960, idealWidth: 1040, minHeight: 680, idealHeight: 760)
    }

    private func finish(_ result: TestResult) {
        controller.record(result)
        let tests = controller.plannedTests
        guard let current, let index = tests.firstIndex(of: current) else { return }
        if index + 1 < tests.count {
            self.current = tests[index + 1]
        } else {
            finished = true
        }
    }
}

/// Un seul test, lancé depuis sa carte.
struct TestSheet: View {
    @EnvironmentObject var controller: CheckController
    @Environment(\.dismiss) private var dismiss
    let test: TestID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(test.title, systemImage: test.symbolName).font(.headline)
                Spacer()
                Button(L("Close", "Fermer")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            TestHost(test: test, profile: controller.profile) { result in
                controller.record(result)
                dismiss()
            }
        }
        .frame(minWidth: 960, idealWidth: 1040, minHeight: 680, idealHeight: 760)
    }
}

private struct WizardHeader: View {
    let step: Int
    let count: Int
    let test: TestID
    let onSkip: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L("Step \(step) of \(count)", "Étape \(step) sur \(count)"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(L("Skip This Test", "Ignorer ce test"), action: onSkip)
                Button(L("Quit", "Quitter"), action: onQuit)
            }
            ProgressView(value: Double(step - 1), total: Double(count))
                .tint(AmanPalette.water)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct WizardSummary: View {
    @EnvironmentObject var controller: CheckController
    let onClose: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AmanPalette.water)
            Text(L("Guided tests finished", "Tests guidés terminés")).font(.title2.bold())
            AmanCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.plannedTests) { test in
                        let result = controller.results[test]
                        HStack(spacing: 10) {
                            Image(systemName: (result?.status ?? .notTested).symbolName)
                                .foregroundStyle((result?.status ?? .notTested).color)
                                .frame(width: 18)
                            Text(test.title).frame(width: 170, alignment: .leading)
                            Text(result.map { $0.status == .notTested ? CheckStatus.notTested.label : $0.summary } ?? CheckStatus.notTested.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            if let result {
                                Text(result.provenance.shortLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 620)
            HStack {
                Button(L("Close", "Fermer"), action: onClose)
                Button(L("View the Report", "Voir le rapport"), action: onReport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(24)
    }
}

/// Aiguillage vers le bon test.
struct TestHost: View {
    let test: TestID
    let profile: DeviceProfile
    let finish: (TestResult) -> Void

    var body: some View {
        switch test {
        case .screen: ScreenTestView(finish: finish)
        case .keyboard: KeyboardTestView(profile: profile, finish: finish)
        case .touchBar: TouchBarTestView(finish: finish)
        case .trackpad: TrackpadTestView(profile: profile, finish: finish)
        case .speakers: SpeakerTestView(finish: finish)
        case .microphone: MicrophoneTestView(finish: finish)
        case .camera: CameraTestView(finish: finish)
        case .touchID: TouchIDTestView(finish: finish)
        case .ports: PortsTestView(profile: profile, finish: finish)
        }
    }
}

/// Mise en page commune des tests : consigne en haut, contenu, actions en bas.
struct TestScaffold<Content: View, Actions: View>: View {
    let title: String
    let instruction: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.bold())
                Text(instruction)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                Spacer()
                actions
            }
            .controlSize(.large)
        }
        .padding(24)
    }
}
