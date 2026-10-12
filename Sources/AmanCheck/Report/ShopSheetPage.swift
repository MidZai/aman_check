import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Fiche A5 pour les boutiques (offre Pro, cahier des charges niveau 2 §8) : nom du Mac,
/// 4 chiffres clés et QR code en grand, à poser à côté de la machine. Sans verdict global ;
/// un blocage éventuel reste affiché en tête, en rouge (règle 4).
struct ShopSheetPage: View {
    /// A5 portrait, en points.
    static let size = CGSize(width: 420, height: 595)

    let report: ConditionReport
    let publication: PublicationRecord
    let logo: Data?

    private typealias Palette = ReportPage.Palette

    var body: some View {
        let summary = ReportSummary(report: report)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    AmanRing(fraction: 1, color: AmanPalette.water).frame(width: 22, height: 22)
                    Text("Aman Check").font(.system(size: 12, weight: .bold))
                }
                Spacer()
                if let logo, let image = NSImage(data: logo) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 110, maxHeight: 34)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(report.profile.displayName).font(.system(size: 20, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(L("Checked on \(Formatters.longDate(report.generatedAt))", "Contrôlé le \(Formatters.longDate(report.generatedAt))"))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
                if let serial = report.measurement(MetricID.serial), serial.value != nil {
                    (Text(L("Serial no. ", "N° de série ")) + Text(serial.displayText).font(.system(size: 11, weight: .semibold, design: .monospaced)))
                        .font(.system(size: 10, weight: .medium))
                }
            }

            // iCloud et MDM bien visibles : un blocage reste rouge, une absence de signal n'est verte que si elle a été lue.
            HStack(spacing: 8) {
                ForEach([MetricID.activationLock, MetricID.mdm], id: \.self) { id in
                    if let m = report.measurement(id) { lockTile(m) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(figures(summary), id: \.title) { figure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(figure.title).font(.system(size: 8.5)).foregroundStyle(Palette.secondary)
                        Text(figure.value).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        if let detail = figure.detail {
                            Text(detail).font(.system(size: 8)).foregroundStyle(Palette.secondary).lineLimit(2)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.rule))
                }
            }

            HStack(alignment: .center, spacing: 14) {
                if let qr = QRCode.image(for: publication.url) {
                    // 150 pt ≈ 53 mm : lisible de loin.
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 150, height: 150)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Scan to view the full report", "Scannez pour voir le rapport complet"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(publication.url).font(.system(size: 8.5, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                    Text(Level2Text.trustLevel2)
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Palette.secondary.opacity(0.6), lineWidth: 0.7))
                    Text(L("Compare the last 4 characters of the serial number with the ones under the Mac.",
                           "Comparez les 4 derniers caractères du n° de série avec ceux gravés sous le Mac."))
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Rectangle().fill(Palette.rule).frame(height: 1)
                Text(Level2Text.disclaimer).font(.system(size: 6.5)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(publication.publicId) · \(L("fingerprint", "empreinte")) \(publication.shortFingerprint)")
                    .font(.system(size: 6.5, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .light)
    }

    private func lockTile(_ m: AmanCore.Measurement) -> some View {
        let tint = Palette.status(m.status)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: m.id == MetricID.activationLock ? "icloud" : "building.2")
                Text(m.id == MetricID.activationLock ? L("iCloud lock", "Verrouillage iCloud") : L("Company management (MDM)", "Gestion d'entreprise (MDM)"))
            }
            .font(.system(size: 8.5, weight: .semibold))
            HStack(spacing: 5) {
                Image(systemName: m.status == .good ? "lock.open" : m.status == .problem ? "lock.fill" : m.status.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(m.displayText).font(.system(size: 12, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.75), lineWidth: 1.5))
    }

    private struct Figure {
        let title: String
        let value: String
        let detail: String?
    }

    /// Quatre chiffres : batterie, SSD, données écrites, tests réalisés. Une donnée absente reste « — ».
    private func figures(_ s: ReportSummary) -> [Figure] {
        func text(_ id: String) -> String? {
            guard let m = report.measurement(id), m.value != nil else { return nil }
            return m.displayText
        }
        var result: [Figure] = []
        if report.profile.hasBattery {
            result.append(Figure(title: L("Battery capacity", "Capacité de la batterie"), value: text(MetricID.batteryHealth) ?? "—",
                                 detail: text(MetricID.batteryCycles).map { L("\($0) cycles", "\($0) cycles") }))
        }
        result.append(Figure(title: L("SSD", "SSD"), value: text(MetricID.storageHealth) ?? "—",
                             detail: text(MetricID.storagePercentageUsed).map { L("wear \($0)", "usure \($0)") }))
        result.append(Figure(title: MetricCatalog.info(for: MetricID.storageDataWritten).label, value: text(MetricID.storageDataWritten) ?? "—",
                             detail: text(MetricID.storagePowerOnHours).map { L("\($0) powered on", "\($0) sous tension") }))
        result.append(Figure(title: L("Guided tests", "Tests guidés"), value: "\(s.testsDone) / \(s.testsPlanned)",
                             detail: L("done", "réalisés")))
        if result.count < 4 {
            result.append(Figure(title: MetricCatalog.info(for: MetricID.ram).label, value: text(MetricID.ram) ?? "—", detail: text(MetricID.chip)))
        }
        return result
    }
}
