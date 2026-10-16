import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Pages A4 du rapport PDF. Toujours claires (le PDF est imprimé ou partagé, quel que soit le thème),
/// lisibles en noir et blanc : chaque statut a une icône ET un texte (spec §8.3).
/// Même méthode qu'Aman Disk (ReportPageView + ImageRenderer).
struct ReportPage: View {
    /// Horodatage imprimé avec son fuseau horaire : « 2026-10-12 16:25 UTC+01:00 ».
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'xxx"
        return formatter.string(from: date)
    }

    static let size = CGSize(width: 595, height: 842)

    enum Content {
        case summary
        case details([DetailBlock])
    }

    /// Bloc de la partie détaillée (une section ou la liste des tests).
    struct DetailBlock: Identifiable {
        let id: String
        let title: String
        let rows: [DetailRow]
    }

    struct DetailRow: Identifiable {
        let id: String
        let label: String
        let value: String
        let status: CheckStatus?
        let provenance: String
        let method: String?
        let note: String?
    }

    let report: ConditionReport
    let content: Content
    let pageNumber: Int
    let pageCount: Int
    /// Niveau 2 : publication en ligne du rapport. `nil` : PDF de niveau 1, sans QR code.
    var publication: PublicationRecord? = nil
    /// Offre Pro : logo du magasin (PNG).
    var logo: Data? = nil

    /// Réglage « QR code hors ligne dans le PDF » (activé par défaut).
    static let offlineQRDefaultsKey = "report.offlineQR"
    static var offlineQREnabled: Bool { UserDefaults.standard.object(forKey: offlineQRDefaultsKey) as? Bool ?? true }

    /// Niveau 1, page 1 : QR code du résumé compact, sans URL (spec §8.4). Le niveau 2 garde son propre QR code.
    private var offlineQR: NSImage? {
        guard publication == nil, pageNumber == 1, Self.offlineQREnabled else { return nil }
        return QRCode.image(for: OfflineSummary.text(for: report), moduleSize: 6)
    }

    enum Palette {
        static let text = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let secondary = Color(red: 0.40, green: 0.40, blue: 0.43)
        static let rule = Color(red: 0.88, green: 0.88, blue: 0.90)
        static let stripe = Color(red: 0.965, green: 0.965, blue: 0.97)
        static let card = Color(red: 0.975, green: 0.975, blue: 0.98)
        static let accent = Color(red: 0.18, green: 0.62, blue: 0.84)

        /// Couleurs foncées pour l'impression (Aman Disk ReportPageView).
        static func status(_ status: CheckStatus) -> Color {
            switch status {
            case .good: return Color(red: 0.14, green: 0.54, blue: 0.24)
            case .watch: return Color(red: 0.79, green: 0.40, blue: 0.0)
            case .problem: return Color(red: 0.80, green: 0.0, blue: 0.08)
            case .manualRequired: return Color(red: 0.10, green: 0.36, blue: 0.75)
            default: return secondary
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.vertical, 12)
            switch content {
            case .summary: summary
            case .details(let blocks): details(blocks)
            }
            Spacer(minLength: 8)
            footer
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .light)
    }

    // MARK: En-tête et pied de page

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                AmanRing(fraction: 1, color: AmanPalette.water).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aman Check").font(.system(size: 13, weight: .bold))
                    Text(ReportText.title).font(.system(size: 9.5)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(L("Condition report as of \(Self.stamp(report.generatedAt))", "Rapport d'état au \(Self.stamp(report.generatedAt))"))
                    .font(.system(size: 9, weight: .semibold))
                Text(L("Report \(report.reportID) · Procedure \(report.procedureVersion) · App \(report.appVersion)",
                       "Rapport \(report.reportID) · Procédure \(report.procedureVersion) · App \(report.appVersion)"))
                if let publication {
                    Text(L("Public ID \(publication.publicId)", "Identifiant public \(publication.publicId)"))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(publication.url)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Palette.text)
                }
                Text(publication == nil ? ReportText.trustLevel1 : Level2Text.trustLevel2)
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Palette.secondary.opacity(0.6), lineWidth: 0.7))
                    .padding(.top, 2)
                if let logo, pageNumber == 1, let image = NSImage(data: logo) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 90, maxHeight: 28).padding(.top, 2)
                }
            }
            .font(.system(size: 8.5))
            .foregroundStyle(Palette.secondary)
            // QR code sur la page 1 : 76 pt ≈ 27 mm (minimum 25 mm), marge blanche comprise dans l'image.
            if let publication, pageNumber == 1, let qr = QRCode.image(for: publication.url) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .padding(.leading, 6)
            } else if let qr = offlineQR {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .padding(.leading, 6)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Palette.rule).frame(height: 1)
            Text(publication == nil ? ReportText.disclaimer : Level2Text.disclaimer)
                .font(.system(size: 7.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if offlineQR != nil {
                // Lexique (spec §3) : aucune promesse d'authenticité ni d'inviolabilité.
                Text(ReportText.offlineQRCaption)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L("Report \(report.reportID)", "Rapport \(report.reportID)"))
                if let publication {
                    Text(L("· fingerprint \(publication.shortFingerprint)", "· empreinte \(publication.shortFingerprint)"))
                }
                Spacer()
                Text(L("Page \(pageNumber) of \(pageCount)", "Page \(pageNumber) sur \(pageCount)"))
            }
            .font(.system(size: 7.5))
            .foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Page 1

    private var summary: some View {
        let s = ReportSummary(report: report)
        return VStack(alignment: .leading, spacing: 12) {
            identity
            if report.simulated {
                banner(status: .watch, symbol: "wrench.and.screwdriver",
                       text: ReportText.simulatedWarning)
            }
            ForEach(s.blockers) { blocker in
                banner(status: .problem, symbol: "lock.trianglebadge.exclamationmark", text: "\(blocker.label)\(L(": ", " : "))\(blocker.displayText). \(blocker.detail ?? "")")
            }

            // iCloud et MDM juste sous l'identité, en grand : ce que l'acheteur doit voir d'abord.
            sectionTitle(L("Locks", "Verrouillages"))
            HStack(alignment: .top, spacing: 8) {
                ForEach([MetricID.activationLock, MetricID.mdm], id: \.self) { id in
                    if let m = report.measurement(id) { keyLockBox(m) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Compte Apple connecté puis mot de passe firmware : une ligne chacun sous les deux encadrés.
            ForEach([MetricID.appleAccount, MetricID.firmwarePassword], id: \.self) { id in
                if let m = report.measurement(id) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        statusIcon(m.status)
                        Text(m.label + L(": ", " : ")).font(.system(size: 8.5, weight: .medium))
                            + Text(m.displayText).font(.system(size: 8.5, weight: .semibold)).foregroundColor(Palette.status(m.status))
                        if let text = m.id == MetricID.appleAccount ? m.detail : m.note {
                            Text("— " + text).font(.system(size: 7.5)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                }
            }

            if s.testsDone < s.testsPlanned {
                banner(status: .notTested, symbol: "exclamationmark.circle",
                       text: L("\(s.testsPlanned - s.testsDone) guided test(s) out of \(s.testsPlanned) not done: see “To check before buying”.",
                               "\(s.testsPlanned - s.testsDone) test(s) guidé(s) sur \(s.testsPlanned) non réalisé(s) : voir « À vérifier avant l'achat »."))
            }
            Text(s.countersText)
                .font(.system(size: 9.5, weight: .medium))

            sectionTitle(L("At a glance", "En résumé"))
            HStack(alignment: .top, spacing: 8) {
                keyCards(s)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle(L("Guided tests", "Tests guidés"))
                    ForEach(report.plannedTests) { test in testLine(test) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle(L("To check before buying", "À vérifier avant l'achat"))
                    let points = ReportInsights.toCheck(report).filter { $0.key != "tests.notTested" }
                    ForEach(points.prefix(7)) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            statusIcon(point.status)
                            Text(point.title).font(.system(size: 8.5)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if points.count > 7 {
                        Text(L("…and \(points.count - 7) more in the detailed report.", "…et \(points.count - 7) autre(s) dans le rapport détaillé."))
                            .font(.system(size: 8)).foregroundStyle(Palette.secondary)
                    }
                    if points.isEmpty {
                        Text(L("Nothing else to check.", "Rien d'autre à vérifier.")).font(.system(size: 8.5)).foregroundStyle(Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var identity: some View {
        let ids = [MetricID.chip, MetricID.ram, MetricID.storageCapacity, MetricID.macOS]
        let line1 = ids.compactMap { report.measurement($0) }.filter { $0.value != nil }.map(\.displayText).joined(separator: " · ")
        var line2: [String] = []
        if let year = report.measurement(MetricID.modelYear), year.value != nil {
            line2.append(L("Model released in \(year.displayText)", "Modèle commercialisé en \(year.displayText)"))
        }
        if let max = report.measurement(MetricID.macOSMax), max.value != nil {
            line2.append(L("latest macOS: \(max.displayText)", "macOS maximal : \(max.displayText)"))
        }
        if let serial = report.measurement(MetricID.serial), serial.value != nil {
            line2.append(L("serial no. \(serial.displayText)", "n° de série \(serial.displayText)"))
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(report.profile.displayName).font(.system(size: 17, weight: .bold))
            Text(line1).font(.system(size: 9.5))
            Text(line2.joined(separator: " · ")).font(.system(size: 8.5)).foregroundStyle(Palette.secondary)
            if let seller = report.sellerName {
                Text(L("Check carried out by: \(seller)", "Contrôle effectué par : \(seller)")).font(.system(size: 8.5)).foregroundStyle(Palette.secondary)
            }
        }
    }

    /// iCloud ou MDM : encadré teinté par le verdict, verdict en gros, icône + texte (lisible en noir et blanc).
    private func keyLockBox(_ m: AmanCore.Measurement) -> some View {
        let tint = Palette.status(m.status)
        let symbol = m.id == MetricID.activationLock ? "icloud" : "building.2"
        let verdict: String
        switch m.status {
        case .good: verdict = "lock.open"
        case .problem: verdict = "lock.fill"
        default: verdict = m.status.symbolName
        }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(m.label).font(.system(size: 9.5, weight: .semibold))
            }
            HStack(spacing: 6) {
                Image(systemName: verdict).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.displayText).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                    Text(m.status.label).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(tint)
                }
            }
            if let note = m.note {
                Text(note).font(.system(size: 7)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.75), lineWidth: 1.5))
    }

    @ViewBuilder
    private func keyCards(_ s: ReportSummary) -> some View {
        if let health = report.measurement(MetricID.batteryHealth) {
            let cycles = report.measurement(MetricID.batteryCycles)
            keyCard(L("Battery", "Batterie"), value: health.value == nil ? "—" : health.displayText,
                    detail: cycles?.value == nil ? health.note : L("\(cycles!.displayText) cycles · \(cycles!.detail ?? "")", "\(cycles!.displayText) cycles · \(cycles!.detail ?? "")"),
                    status: health.status)
        }
        if let ssd = report.measurement(MetricID.storageHealth) {
            let hours = report.measurement(MetricID.storagePowerOnHours)
            let written = report.measurement(MetricID.storageDataWritten)
            let wear = report.measurement(MetricID.storagePercentageUsed)
            keyCard(L("SSD", "SSD"), value: ssd.displayText,
                    detail: [hours?.value == nil ? nil : L("\(hours!.displayText) powered on", "\(hours!.displayText) sous tension"),
                             written?.value == nil ? nil : L("\(written!.displayText) written", "\(written!.displayText) écrits"),
                             wear?.value == nil ? nil : L("wear \(wear!.displayText)", "usure \(wear!.displayText)")].compactMap { $0 }.joined(separator: " · "),
                    status: ssd.status)
        }
        keyCard(L("Configuration", "Configuration"),
                value: [MetricID.ram, MetricID.storageCapacity].compactMap { report.measurement($0) }.filter { $0.value != nil }.map(\.displayText).joined(separator: " · "),
                detail: report.measurement(MetricID.gpu)?.displayText, status: nil)
        keyCard(L("Tests", "Tests"), value: "\(s.testsDone) / \(s.testsPlanned)", detail: L("guided tests done", "tests guidés réalisés"), status: nil)
    }

    private func keyCard(_ title: String, value: String, detail: String?, status: CheckStatus?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            if let detail { Text(detail).font(.system(size: 7.5)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
            if let status, status != .info {
                HStack(spacing: 3) {
                    statusIcon(status)
                    Text(status.label).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Palette.status(status))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.rule))
    }

    private func testLine(_ test: TestID) -> some View {
        let result = report.result(test)
        let status = result?.status ?? .notTested
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            statusIcon(status)
            // Assez large pour « Rétroéclairage du clavier » ; un nom plus long passe à la ligne au lieu d'être tronqué.
            Text(test.title).font(.system(size: 8.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                .frame(width: 112, alignment: .leading)
            Text(result.map { $0.status == .notTested ? CheckStatus.notTested.label : $0.summary } ?? CheckStatus.notTested.label)
                .font(.system(size: 8))
                .foregroundStyle(status == .notTested ? Palette.secondary : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            if let result, result.status != .notTested {
                Text(result.provenance.shortLabel).font(.system(size: 7)).foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: Pages détaillées

    private func details(_ blocks: [DetailBlock]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(block.title).padding(.bottom, 4)
                    ForEach(Array(block.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.label).frame(width: 165, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if let status = row.status { statusIcon(status) }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.value).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                                    if let note = row.note {
                                        Text(note).font(.system(size: 7)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(row.provenance).font(.system(size: 7))
                                if let method = row.method {
                                    Text(method).font(.system(size: 6.5, design: .monospaced)).multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 150, alignment: .trailing)
                        }
                        .font(.system(size: 8.5))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(index.isMultiple(of: 2) ? Color.white : Palette.stripe)
                    }
                }
            }
        }
    }

    /// Découpe la partie détaillée en pages (hauteur estimée de chaque ligne).
    static func detailPages(for report: ConditionReport) -> [[DetailBlock]] {
        var blocks: [DetailBlock] = []
        for section in MetricSection.allCases {
            let rows = report.measurements.filter { MetricCatalog.info(for: $0.id).section == section }.map { m -> DetailRow in
                let info = MetricCatalog.info(for: m.id)
                return DetailRow(id: m.id, label: m.label, value: m.displayText,
                                 status: info.isJudged || m.value == nil || m.status == .manualRequired ? m.status : nil,
                                 provenance: m.value == nil ? L("Not measured", "Non mesuré") : m.provenance.label, method: m.method,
                                 note: sentence(m.detail, m.note))
            }
            if !rows.isEmpty { blocks.append(DetailBlock(id: section.rawValue, title: section.title, rows: rows)) }
        }
        let testRows = report.plannedTests.map { test -> DetailRow in
            let r = report.result(test)
            return DetailRow(id: "test.\(test.rawValue)", label: test.title,
                             value: r.map { $0.status == .notTested ? "\(CheckStatus.notTested.label) (\($0.outcome.label.lowercased()))" : $0.summary } ?? CheckStatus.notTested.label,
                             status: r?.status ?? .notTested, provenance: r?.provenance.label ?? "—",
                             method: r.map { Formatters.date($0.completedAt) }, note: r?.details.joined(separator: " · "))
        }
        blocks.append(DetailBlock(id: "tests", title: L("Guided tests", "Tests guidés"), rows: testRows))

        // Pagination : hauteur utile estimée, avec une marge de sécurité (le pied de page ne doit jamais déborder).
        let available = 590.0
        var pages: [[DetailBlock]] = []
        var current: [DetailBlock] = []
        var used = 0.0
        func rowHeight(_ r: DetailRow) -> Double {
            let noteLines = Double(((r.note ?? "").count + 90) / 95)
            let methodLines = Double(((r.method ?? "").count + 39) / 40)
            return max(16, 8 + max(11 + noteLines * 9, methodLines * 8 + 9))
        }
        for block in blocks {
            var rows: [DetailRow] = []
            var blockUsed = 22.0
            for row in block.rows {
                let h = rowHeight(row)
                if used + blockUsed + h > available {
                    if !rows.isEmpty { current.append(DetailBlock(id: block.id + "\(pages.count)", title: block.title, rows: rows)) }
                    pages.append(current)
                    current = []
                    used = 0
                    rows = []
                    blockUsed = 22
                }
                rows.append(row)
                blockUsed += h
            }
            if !rows.isEmpty { current.append(DetailBlock(id: block.id + "-\(pages.count)", title: block.title, rows: rows)) }
            used += blockUsed + 10
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// « 4 derniers caractères. L'acheteur peut… » : deux textes réunis en phrases.
    static func sentence(_ a: String?, _ b: String?) -> String? {
        let parts = [a, b].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.map { $0.hasSuffix(".") || $0.hasSuffix("!") || $0.hasSuffix("?") ? $0 : $0 + "." }.joined(separator: " ")
    }

    // MARK: Éléments

    private func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Rectangle().fill(Palette.rule).frame(height: 1)
        }
    }

    private func statusIcon(_ status: CheckStatus) -> some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Palette.status(status))
    }

    private func banner(status: CheckStatus, symbol: String, text: String) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Palette.status(status)).frame(width: 3)
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(Palette.status(status))
                Text(text).font(.system(size: 9, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .background(Palette.status(status).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Toutes les pages d'un rapport : la page 1 seule (rapport simple) ou suivie des pages détaillées.
enum ReportPages {
    static func make(_ report: ConditionReport, detailed: Bool, publication: PublicationRecord? = nil, logo: Data? = nil) -> [ReportPage] {
        let detailPages = detailed ? ReportPage.detailPages(for: report) : []
        let count = 1 + detailPages.count
        var pages = [ReportPage(report: report, content: .summary, pageNumber: 1, pageCount: count, publication: publication, logo: logo)]
        for (index, blocks) in detailPages.enumerated() {
            pages.append(ReportPage(report: report, content: .details(blocks), pageNumber: index + 2, pageCount: count,
                                    publication: publication, logo: logo))
        }
        return pages
    }
}
