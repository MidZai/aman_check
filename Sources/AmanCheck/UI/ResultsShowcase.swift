import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Haut de la page de résultats : ce que l'acheteur veut voir d'abord (le Mac, ses caractéristiques,
/// sa batterie, son SSD), présenté comme une fiche produit. Aucune promesse : chaque chiffre est mesuré.
struct MachineShowcase: View {
    @EnvironmentObject var controller: CheckController
    let report: ConditionReport

    var body: some View {
        AmanCard(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        MacVisual(profile: controller.profile, size: 170)
                        identity
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        MacVisual(profile: controller.profile, size: 150)
                        identity
                    }
                }
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 20, alignment: .topLeading)],
                          alignment: .leading, spacing: 18) {
                    ForEach(specs, id: \.label) { spec in
                        SpecItem(spec: spec)
                    }
                }
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.profile.displayName)
                .font(.system(size: 30, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(tagline)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TrustBadge()
                Text(L("Checked on \(Formatters.longDate(report.generatedAt))", "Contrôlé le \(Formatters.longDate(report.generatedAt))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    /// « Sorti en 2019 · compatible jusqu'à macOS 26 Tahoe · n° ••••MD6R ».
    private var tagline: String {
        var parts: [String] = []
        if let year = controller.measurement(MetricID.modelYear), year.value != nil {
            parts.append(L("Released in \(year.displayText)", "Sorti en \(year.displayText)"))
        }
        if let max = controller.measurement(MetricID.macOSMax), max.value != nil {
            parts.append(L("runs up to \(max.displayText)", "compatible jusqu'à \(max.displayText)"))
        }
        if let serial = controller.measurement(MetricID.serial), serial.value != nil {
            parts.append(L("serial \(serial.displayText)", "n° de série \(serial.displayText)"))
        }
        return parts.joined(separator: " · ")
    }

    struct Spec {
        let symbol: String
        let label: String
        let value: String
        let detail: String?
    }

    private var specs: [Spec] {
        func spec(_ id: String, _ symbol: String) -> Spec? {
            guard let m = controller.measurement(id), m.value != nil else { return nil }
            return Spec(symbol: symbol, label: m.label, value: m.displayText, detail: m.detail)
        }
        var list: [Spec?] = [
            spec(MetricID.chip, "cpu"),
            spec(MetricID.ram, "memorychip"),
            spec(MetricID.storageCapacity, "internaldrive"),
            spec(MetricID.gpu, "square.3.layers.3d"),
            spec(MetricID.display, "display"),
            spec(MetricID.macOS, "apple.logo")
        ]
        // Cœurs : rattachés au processeur.
        if let cores = controller.measurement(MetricID.cpuCores), cores.value != nil, let cpu = list[0] {
            list[0] = Spec(symbol: cpu.symbol, label: cpu.label, value: cpu.value,
                           detail: [cores.displayText, cpu.detail].compactMap { $0 }.joined(separator: " · "))
        }
        return list.compactMap { $0 }
    }
}

private struct SpecItem: View {
    let spec: MachineShowcase.Spec

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: spec.symbol)
                .font(.system(size: 18))
                .foregroundStyle(AmanPalette.water)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                Text(spec.value)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = spec.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Chiffres clés, en grand : batterie, santé du SSD, heures du SSD, données écrites.
struct KeyFigures: View {
    @EnvironmentObject var controller: CheckController

    var body: some View {
        AdaptiveRow(minItemWidth: 240) {
            if let health = controller.measurement(MetricID.batteryHealth) {
                let cycles = controller.measurement(MetricID.batteryCycles)
                let condition = controller.measurement(MetricID.batteryCondition)
                Figure(title: L("Battery", "Batterie"),
                       visual: .ring(AmanRing(fraction: health.value?.doubleValue.map { $0 / 100 },
                                              color: AmanRing.color(for: health.status), center: .symbol("bolt.fill"))),
                       value: health.value == nil ? nil : health.displayText,
                       caption: health.value == nil ? health.note : health.detail,
                       lines: [cycles?.value.map { _ in L("\(cycles!.displayText) cycles", "\(cycles!.displayText) cycles") + (cycles!.detail.map { " " + $0 } ?? "") },
                               condition.map { L("Condition: \($0.displayText)", "État : \($0.displayText)") }].compactMap { $0 },
                       status: health.status,
                       help: MetricCatalog.info(for: MetricID.batteryHealth).help)
            }
            if let ssd = controller.measurement(MetricID.storageHealth) {
                let wear = controller.measurement(MetricID.storagePercentageUsed)
                let remaining = wear?.value?.intValue.map { Double(max(0, 100 - Int($0))) / 100 }
                Figure(title: ssd.label,
                       visual: .ring(AmanRing(fraction: remaining, color: AmanRing.color(for: ssd.status))),
                       // Durée de vie restante en grand (comme l'anneau d'Aman Disk), l'état en texte dessous.
                       value: remaining.map { "\(Int(($0 * 100).rounded()))\(Formatters.unitSpace)%" } ?? (ssd.value == nil ? nil : ssd.displayText),
                       caption: remaining != nil ? L("remaining life", "de durée de vie restante") : (ssd.value == nil ? ssd.note : nil),
                       lines: [ssd.value == nil ? nil : ssd.displayText,
                               wear?.value == nil ? nil : L("Wear: \(wear!.displayText)", "Usure : \(wear!.displayText)")].compactMap { $0 },
                       status: ssd.status,
                       help: MetricCatalog.info(for: MetricID.storageHealth).help)
            }
            if let hours = controller.measurement(MetricID.storagePowerOnHours) {
                Figure(title: hours.label, visual: .symbol("clock"),
                       value: hours.value == nil ? nil : hours.displayText,
                       caption: hours.value == nil ? hours.note : hours.detail, lines: [], status: nil,
                       help: MetricCatalog.info(for: hours.id).help)
            }
            if let written = controller.measurement(MetricID.storageDataWritten) {
                Figure(title: written.label, visual: .symbol("square.and.pencil"),
                       value: written.value == nil ? nil : written.displayText,
                       caption: written.value == nil ? written.note : written.detail, lines: [], status: nil,
                       help: MetricCatalog.info(for: written.id).help)
            }
        }
    }
}

private struct Figure: View {
    enum Visual {
        case ring(AmanRing)
        case symbol(String)
    }

    let title: String
    let visual: Visual
    let value: String?
    let caption: String?
    let lines: [String]
    let status: CheckStatus?
    let help: String?

    var body: some View {
        AmanCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let help { InfoButton(help).font(.caption) }
                    Spacer(minLength: 4)
                    if let status, status.isJudgement || status == .manualRequired {
                        StatusPill(status)
                    }
                }
                HStack(alignment: .center, spacing: 14) {
                    switch visual {
                    case .ring(let ring):
                        ring.frame(width: 64, height: 64)
                    case .symbol(let name):
                        Image(systemName: name)
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(AmanPalette.ink, in: Circle())
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value ?? "—")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(value == nil ? .tertiary : .primary)
                        if let caption {
                            Text(caption)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
