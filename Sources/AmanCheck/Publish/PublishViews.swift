import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Bloc « Rapport vérifiable » de l'écran Rapport (cahier des charges niveau 2, §8) :
/// non publié, publication en cours, publié, erreur.
struct VerifiableReportSection: View {
    @EnvironmentObject var controller: CheckController
    @EnvironmentObject var publisher: PublishController
    let report: ConditionReport
    let detailed: Bool

    var body: some View {
        Section {
            if let record = publisher.publication(for: report.reportID) {
                publishedView(record)
            } else if publisher.state == .publishing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Publishing…", "Publication en cours…"))
                }
            } else {
                notPublishedView
            }
        } header: {
            Text(Level2Text.verifiableReport)
        } footer: {
            if publisher.publication(for: report.reportID) == nil {
                Text(L("Optional and paid. A public page, opened with a link or a QR code, shows that this report has not been changed since it was published.",
                       "Facultatif et payant. Une page publique, ouverte par un lien ou un QR code, montre que ce rapport n'a pas été modifié depuis sa publication."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notPublishedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .failed(let error) = publisher.state, !publisher.showSheet {
                ErrorCallout(error: error)
            }
            Button {
                publisher.resetError()
                publisher.showSheet = true
            } label: {
                Label(L("Publish a Verifiable Report…", "Publier un rapport vérifiable…"), systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(report.simulated)
            if report.simulated {
                Text(PublishError.simulatedProfile.message).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func publishedView(_ record: PublicationRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let qr = QRCode.image(for: record.url) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 112, height: 112)
                        .accessibilityLabel(L("QR code of the report link", "QR code du lien du rapport"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(Level2Text.trustLevel2, systemImage: "checkmark.seal")
                        .font(.caption.weight(.semibold))
                    Text(record.url)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Valid until \(Formatters.longDate(record.validUntil))", "Valable jusqu'au \(Formatters.longDate(record.validUntil))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if publisher.hasChangesSincePublication(controller.report) {
                Text(L("Changes made since publication (seller, tests) are not in the published report. Publish again to include them; it is free for this Mac.",
                       "Les changements faits depuis la publication (vendeur, tests) ne figurent pas dans le rapport publié. Republiez pour les inclure ; c'est gratuit pour ce Mac."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Publish Again…", "Republier…")) { publisher.showSheet = true }
            }
            HStack {
                Button(L("Copy Link", "Copier le lien")) { publisher.copy(record.url) }
                Button(L("Copy Text for the Listing", "Copier le texte pour l'annonce")) {
                    publisher.copy(publisher.listingText(for: record, report: report))
                }
            }
            if publisher.license?.isPro == true, let archive = publisher.published[report.reportID] {
                Button(L("Export Shop Sheet (A5)…", "Exporter la fiche (A5)…")) {
                    ReportExporter.exportSheet(archive, logo: publisher.license?.logoData)
                }
            }
            if let entry = publisher.entries.first(where: { $0.id == record.publicId }) {
                Button(role: .destructive) {
                    Task { await publisher.withdraw(entry) }
                } label: {
                    Text(L("Withdraw from Publication", "Retirer de la publication"))
                }
                .disabled(publisher.withdrawing != nil)
            }
            if case .failed(let error) = publisher.state { ErrorCallout(error: error) }
        }
    }
}

/// Publications précédentes, pour pouvoir les retirer à tout moment.
struct PreviousPublicationsSection: View {
    @EnvironmentObject var publisher: PublishController
    let currentReportID: String

    var body: some View {
        let previous = publisher.entries.filter { !$0.withdrawn && $0.reportID != currentReportID }
        if !previous.isEmpty {
            Section(L("Previous publications", "Publications précédentes")) {
                ForEach(previous) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.modelName).lineLimit(1)
                            Text("\(entry.id) · \(Formatters.longDate(entry.generatedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Withdraw", "Retirer"), role: .destructive) {
                            Task { await publisher.withdraw(entry) }
                        }
                        .disabled(publisher.withdrawing != nil)
                    }
                }
            }
        }
    }
}

private struct ErrorCallout: View {
    @EnvironmentObject var publisher: PublishController
    let error: PublishError

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if error == .privacyCheckFailed, let detail = publisher.privacyIssueText {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if error.offersPurchase {
                Button(L("Get a Key", "Obtenir une clé")) { publisher.openPurchasePage() }
            }
        }
        .font(.callout)
    }
}

/// Feuille de confirmation avant envoi (§3, §10) : ce qui sera envoyé et ce qui ne le sera jamais,
/// mot pour mot ; clé de licence ; « Publier » et « Annuler » de même poids visuel.
struct PublishSheet: View {
    @EnvironmentObject var controller: CheckController
    @EnvironmentObject var publisher: PublishController
    @Environment(\.dismiss) private var dismiss
    let report: ConditionReport

    var body: some View {
        let summary = ReportSummary(report: report)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Publish a verifiable report", "Publier un rapport vérifiable")).font(.title2.bold())
                Text(L("The report will be viewable by anyone with the link, at \(PublishClient.displayHost). It is published exactly as shown in the preview.",
                       "Le rapport sera consultable par toute personne ayant le lien, sur \(PublishClient.displayHost). Il est publié tel qu'il apparaît dans l'aperçu."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let warning = Level2Text.publishedAsIs(untested: summary.testsPlanned - summary.testsDone, blockers: summary.blockers.count) {
                Callout(tint: .orange, symbol: "exclamationmark.triangle") {
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                list(Level2Text.sentTitle, Level2Text.sent, symbol: "arrow.up.circle", tint: AmanPalette.water)
                list(Level2Text.neverSentTitle, Level2Text.neverSent, symbol: "lock.circle", tint: .secondary)
            }

            if let seller = report.sellerName {
                Text(L("Seller or shop: \(seller). ", "Vendeur ou magasin : \(seller). ") + Level2Text.sellerNameReminder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
            licenseField

            if case .failed(let error) = publisher.state { ErrorCallout(error: error) }

            HStack(spacing: 10) {
                Text(Level2Text.nothingSentWithoutConsent).font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Même poids visuel : aucun des deux n'est mis en avant.
                Button(L("Cancel", "Annuler")) {
                    publisher.resetError()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .frame(minWidth: 110)
                Button {
                    Task { await publisher.publish(report) }
                } label: {
                    if publisher.state == .publishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("Publish", "Publier"))
                    }
                }
                .frame(minWidth: 110)
                .disabled(publisher.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || publisher.state == .publishing)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 640)
        // Aucune requête à l'ouverture : le solde n'est demandé qu'avec « Vérifier » (règle 11).
    }

    private var licenseField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L("License key", "Clé de licence"), text: $publisher.licenseKey, prompt: Text("ACK-XXXX-XXXX-XXXX-XXXX"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { Task { await publisher.checkLicense() } }
                Button(L("Check", "Vérifier")) { Task { await publisher.checkLicense() } }
                    .disabled(publisher.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || publisher.checkingLicense)
            }
            HStack {
                if publisher.checkingLicense {
                    ProgressView().controlSize(.small)
                } else if let license = publisher.license {
                    Label(balance(license), systemImage: license.active ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(license.active ? Color.secondary : Color.orange)
                } else if let error = publisher.licenseError {
                    Label(error.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Spacer()
                Button(L("Get a Key", "Obtenir une clé")) { publisher.openPurchasePage() }
                    .buttonStyle(.link)
            }
            .font(.callout)
        }
    }

    private func balance(_ license: PublishClient.LicenseInfo) -> String {
        if license.isPro {
            let end = license.validUntil.map { Formatters.longDate($0) } ?? "—"
            return license.active ? L("Pro plan, until \(end)", "Offre Pro, jusqu'au \(end)") : L("Pro plan ended on \(end)", "Offre Pro terminée le \(end)")
        }
        let n = license.creditsRemaining ?? 0
        return n == 1 ? L("1 publication left", "1 publication restante") : L("\(n) publications left", "\(n) publications restantes")
    }

    private func list(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AmanDesign.cardBackground, in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(AmanDesign.cardBorder))
    }
}
