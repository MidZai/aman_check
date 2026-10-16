import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Page « Performance » (spec §7.8) : avertissement, lancement explicite, progression en direct, résultats.
struct PerformanceView: View {
    @EnvironmentObject var controller: CheckController
    @ObservedObject var runner: PerformanceRunner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AmanDesign.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Performance", "Performance")).font(.title2.bold())
                    Text(L("About a minute of full load to see whether this Mac keeps its performance as it heats up. A Mac that cools badly (dead fan, dried thermal paste) slows down. This is not a score.",
                           "Environ une minute de pleine charge pour voir si ce Mac garde ses performances en chauffant. Un Mac qui refroidit mal (ventilateur hors service, pâte thermique sèche) ralentit. Ce n'est pas une note."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if runner.isRunning {
                    running
                } else {
                    Callout(tint: .orange, symbol: "thermometer.medium") {
                        Text(L("Before you start", "Avant de commencer")).font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("The Mac will warm up and the fans will spin up: this is normal.",
                                   "Le Mac va chauffer et les ventilateurs vont souffler : c'est normal."))
                            if controller.profile.hasBattery {
                                Text(L("Plug in the power adapter if you can: on battery, macOS may slow the Mac down.",
                                       "Branchez le chargeur si possible : sur batterie, macOS peut ralentir le Mac."))
                            }
                            Text(L("Don't use the Mac during the test, and quit heavy apps first.",
                                   "N'utilisez pas le Mac pendant le test, et quittez d'abord les apps lourdes."))
                        }
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(runner.state == .finished ? L("Run Again", "Relancer le test") : L("Run the Test", "Lancer le test")) {
                            controller.runPerformance()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text(L("About \(Int(PerformanceRunner.totalSeconds)) seconds", "Environ \(Int(PerformanceRunner.totalSeconds)) secondes"))
                            .foregroundStyle(.secondary)
                    }
                }

                results
            }
            .padding(AmanDesign.pagePadding)
            .frame(maxWidth: AmanDesign.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var running: some View {
        AmanCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if case .running(let stage) = runner.state {
                        Label(stage.title, systemImage: "speedometer").font(.headline)
                    }
                    Spacer()
                    Button(L("Cancel", "Annuler"), role: .cancel) { runner.cancel() }
                }
                ProgressView(value: runner.progress)
                    .tint(AmanPalette.water)
                AdaptiveRow(minItemWidth: 180) {
                    StatTile(label: L("Last measurement", "Dernière mesure"), value: runner.lastValue)
                    StatTile(label: L("Processor temperature", "Température du processeur"),
                             value: runner.temperature.map { Formatters.temperature(Int($0.rounded())) },
                             unavailableText: CheckStatus.unavailable.label)
                    if controller.profile.hasFan != false {
                        StatTile(label: L("Fan speed", "Vitesse des ventilateurs"),
                                 value: runner.fanSpeed.map(SensorAnalysis.fanSpeedText),
                                 unavailableText: CheckStatus.unavailable.label)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let items = controller.performance
        if !(items.count == 1 && items.first?.status == .notTested && runner.state == .idle) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Results", "Résultats"))
                AdaptiveRow(minItemWidth: 220) {
                    ForEach(items) { m in
                        let info = MetricCatalog.info(for: m.id)
                        StatTile(label: m.label,
                                 value: m.value == nil ? nil : m.displayText,
                                 detail: m.note ?? m.detail,
                                 status: info.isJudged ? m.status : nil,
                                 help: info.help,
                                 unavailableText: m.note ?? m.status.label)
                    }
                }
                Text(L("No reference yet for your chip? Send the JSON of your report (Export Report as JSON) in an issue on GitHub to help fill the reference table.",
                       "Pas encore de référence pour votre puce ? Envoyez le JSON de votre rapport (Exporter le rapport en JSON) dans une issue sur GitHub pour enrichir la table de référence."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
