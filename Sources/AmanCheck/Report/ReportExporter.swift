import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmanCore
import DiskHealthCore

/// Exports : PDF (rendu natif des pages A4), JSON du rapport, export de diagnostic (correctifs §7).
@MainActor
enum ReportExporter {
    /// `archive` : rapport publié (niveau 2) ; le PDF porte alors le QR code, le lien et l'empreinte.
    /// Un PDF exporté avant publication reste un PDF de niveau 1.
    static func exportPDF(_ report: ConditionReport, detailed: Bool, archive: PublishedReportArchive? = nil, logo: Data? = nil) {
        let report = archive?.report ?? report
        guard let url = savePanel(name: fileName(report, ext: "pdf"), type: .pdf) else { return }
        do {
            try writePDF(report, detailed: detailed, publication: archive?.publication, logo: logo, to: url)
            // Archive locale à côté du PDF (spec §8.3) : le rapport, et le bloc `publication` s'il a été publié.
            // Un fichier .json déjà présent n'est jamais écrasé : suffixe numérique.
            try? archiveData(report, archive: archive).write(to: Self.freeJSONURL(nextTo: url))
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error)
        }
    }

    /// `nom.json`, ou `nom-2.json`, `nom-3.json`… si le fichier existe déjà.
    static func freeJSONURL(nextTo pdf: URL) -> URL {
        let base = pdf.deletingPathExtension()
        var candidate = base.appendingPathExtension("json")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-\(n)").appendingPathExtension("json")
            n += 1
        }
        return candidate
    }

    private static func archiveData(_ report: ConditionReport, archive: PublishedReportArchive?) throws -> Data {
        if let archive { return try ReportCoding.encoder().encode(archive) }
        return try ReportCoding.encode(report)
    }

    static func writePDF(_ report: ConditionReport, detailed: Bool, publication: PublicationRecord? = nil, logo: Data? = nil, to url: URL) throws {
        try render(ReportPages.make(report, detailed: detailed, publication: publication, logo: logo), size: ReportPage.size,
                   title: L("Condition report — \(report.profile.displayName)", "Rapport d'état — \(report.profile.displayName)"),
                   appVersion: report.appVersion, to: url)
    }

    /// Fiche A5 pour les boutiques (offre Pro) : nom du Mac, 4 chiffres clés, QR code en grand.
    static func exportSheet(_ archive: PublishedReportArchive, logo: Data?) {
        let report = archive.report
        guard let url = savePanel(name: L("Sheet", "Fiche") + " – " + fileName(report, ext: "pdf"), type: .pdf) else { return }
        do {
            try writeSheet(archive, logo: logo, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { showError(error) }
    }

    static func writeSheet(_ archive: PublishedReportArchive, logo: Data?, to url: URL) throws {
        try render([ShopSheetPage(report: archive.report, publication: archive.publication, logo: logo)], size: ShopSheetPage.size,
                   title: L("Sheet — \(archive.report.profile.displayName)", "Fiche — \(archive.report.profile.displayName)"),
                   appVersion: archive.report.appVersion, to: url)
    }

    private static func render<Page: View>(_ pages: [Page], size: CGSize, title: String, appVersion: String, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: size)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Aman Check \(appVersion)"]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(size)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func exportJSON(_ report: ConditionReport, archive: PublishedReportArchive? = nil) {
        guard let url = savePanel(name: fileName(report, ext: "json"), type: .json) else { return }
        do {
            try archiveData(archive?.report ?? report, archive: archive).write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { showError(error) }
    }

    /// JSON brut de tout ce qui a été lu + journal des événements de test, pour les testeurs.
    /// Le numéro de série complet n'y figure jamais.
    static func exportDiagnostic(_ report: ConditionReport) {
        struct Diagnostic: Encodable {
            let report: ConditionReport
            let raw: [String: String]
            let events: [DiagnosticLog.Entry]
            let system: [String: String]
        }
        guard let url = savePanel(name: "AmanCheck-diagnostic-\(report.profile.modelIdentifier).json", type: .json) else { return }
        let (entries, raw) = DiagnosticLog.shared.snapshot()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let system = ["hw.model": SystemReader.modelIdentifier,
                      "macOS": "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
                      "build": SystemReader.sysctlString("kern.osversion") ?? "",
                      "arch": SystemReader.isAppleSilicon ? "arm64" : "x86_64"]
        do {
            try encoder().encode(Diagnostic(report: report, raw: raw, events: entries, system: system)).write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { showError(error) }
    }

    /// Impression / aperçu avant impression via un PDF temporaire ouvert dans Aperçu.
    static func preview(_ report: ConditionReport, detailed: Bool, archive: PublishedReportArchive? = nil, logo: Data? = nil) {
        let report = archive?.report ?? report
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(report, ext: "pdf"))
        do {
            try writePDF(report, detailed: detailed, publication: archive?.publication, logo: logo, to: url)
            NSWorkspace.shared.open(url)
        } catch { showError(error) }
    }

    private static func encoder() -> JSONEncoder { ReportCoding.encoder() }

    private static func fileName(_ report: ConditionReport, ext: String) -> String {
        let day = ISO8601DateFormatter.string(from: report.generatedAt, timeZone: .current, formatOptions: [.withFullDate])
        let model = report.profile.displayName.replacingOccurrences(of: "/", with: "-")
        return "\(L("Condition report", "Rapport d'état")) – \(model) – \(day).\(ext)"
    }

    private static func savePanel(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
