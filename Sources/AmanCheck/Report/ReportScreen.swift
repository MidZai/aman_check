import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Page « Rapport » : aperçu fidèle des pages A4 exportées, options et exports.
struct ReportScreen: View {
    @EnvironmentObject var controller: CheckController
    @EnvironmentObject var publisher: PublishController
    @AppStorage("report.detailed") private var detailed = true

    var body: some View {
        if controller.phase != .results {
            VStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("The report appears after the check", "Le rapport apparaît après le contrôle"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button(L("Run the Check", "Lancer le contrôle")) {
                    controller.selection = .overview
                    Task { await controller.runAnalysis() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let live = controller.report
            // Publié : l'aperçu et les exports reprennent exactement le rapport en ligne (niveau 2).
            let archive = publisher.published[live.reportID]
            let report = archive?.report ?? live
            let pages = ReportPages.make(report, detailed: detailed, publication: archive?.publication, logo: logo)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(pages.indices, id: \.self) { index in
                            pages[index]
                                .scaleEffect(1.15, anchor: .top)
                                .frame(width: ReportPage.size.width * 1.15, height: ReportPage.size.height * 1.15)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .underPageBackgroundColor))

                Divider()
                options(report: report, archive: archive, pageCount: pages.count)
                    .frame(width: 320)
            }
            .sheet(isPresented: $publisher.showSheet) {
                PublishSheet(report: controller.report)
                    .environmentObject(controller)
                    .environmentObject(publisher)
            }
        }
    }

    /// Offre Pro : logo du magasin sur le PDF.
    private var logo: Data? { publisher.license?.isPro == true ? publisher.license?.logoData : nil }

    private func options(report: ConditionReport, archive: PublishedReportArchive?, pageCount: Int) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ReportText.title).font(.title2.bold())
                    Text(L("as of \(Formatters.longDate(report.generatedAt))", "au \(Formatters.longDate(report.generatedAt))"))
                        .foregroundStyle(.secondary)
                    TrustBadge().padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            Section(L("Content", "Contenu")) {
                Picker(L("Report", "Rapport"), selection: $detailed) {
                    Text(L("Simple (1 page)", "Simple (1 page)")).tag(false)
                    Text(L("Detailed (\(max(pageCount, 2)) pages)", "Détaillé (\(max(pageCount, 2)) pages)")).tag(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    TextField(L("Seller or shop (optional)", "Vendeur ou magasin (facultatif)"), text: $controller.sellerName)
                    Text(Level2Text.sellerNameReminder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("Serial number", "N° de série")) {
                    Text(L("last 4 characters", "4 derniers caractères")).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    publisher.exportPDF(report, detailed: detailed)
                } label: {
                    Label(L("Export as PDF…", "Exporter en PDF…"), systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Envoi direct à l'acheteur depuis ce Mac : AirDrop, Messages, Mail… (retour Reddit).
                ShareButton(title: L("Share…", "Partager…")) {
                    publisher.shareablePDF(report, detailed: detailed).map { [$0] } ?? []
                }
                .frame(maxWidth: .infinity)
                Button(L("Open in Preview to Print", "Ouvrir dans Aperçu pour imprimer")) {
                    ReportExporter.preview(report, detailed: detailed, archive: archive, logo: logo)
                }
                Button(L("Export as JSON…", "Exporter en JSON…")) {
                    ReportExporter.exportJSON(report, archive: archive)
                }
            } footer: {
                Text(Level2Text.nothingSentWithoutConsent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if PublishClient.isAvailable {
                VerifiableReportSection(report: report, detailed: detailed)
                PreviousPublicationsSection(currentReportID: report.reportID)
            }
        }
        .formStyle(.grouped)
    }
}
