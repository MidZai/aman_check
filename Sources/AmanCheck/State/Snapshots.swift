import SwiftUI
import AppKit
import AmanCore

/// Mode de vérification visuelle (développement) : `--snapshot <dossier>` rend les écrans principaux
/// en PNG et le rapport en PDF, puis quitte. Utilisé pour comparer avec les captures d'Aman Disk.
@MainActor
enum Snapshots {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    private static var started = false

    static func runIfRequested(_ controller: CheckController, publisher: PublishController) {
        guard let dir = directory, !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let appearance = ProcessInfo.processInfo.arguments.contains("--light") ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        NSApp.appearance = appearance
        Task {
            render(OverviewView().environmentObject(controller).environmentObject(publisher), size: CGSize(width: 1040, height: 860), to: dir.appendingPathComponent("1-accueil.png"))
            await controller.runAnalysis()
            render(OverviewView().environmentObject(controller).environmentObject(publisher), size: CGSize(width: 1100, height: 2700), to: dir.appendingPathComponent("2-resultats.png"))
            render(TestsView().environmentObject(controller).environmentObject(publisher), size: CGSize(width: 1040, height: 1100), to: dir.appendingPathComponent("3-tests.png"))
            for test in [TestID.screen, .keyboard, .touchBar, .trackpad, .speakers, .microphone, .ports] {
                render(TestHost(test: test, profile: controller.profile) { _ in }.environmentObject(controller),
                       size: CGSize(width: 1040, height: 720), to: dir.appendingPathComponent("4-test-\(test.rawValue).png"))
            }
            try? ReportExporter.writePDF(controller.report, detailed: true, to: dir.appendingPathComponent("5-rapport.pdf"))
            // Rapport en JSON : permet de comparer les mesures d'une version à l'autre (même encodage que le niveau 2).
            try? ReportCoding.encode(controller.report).write(to: dir.appendingPathComponent("5-rapport.json"))
            // Niveau 2 : publication fictive (aucun réseau), pour vérifier l'en-tête, le QR code et la fiche A5.
            let sample = PublicationRecord(publicId: "7K3P-Q2XD-M4RT", url: "https://aman-check.invalid/r/7K3P-Q2XD-M4RT",
                                           sha256: String(repeating: "3fa9c2e1", count: 8), publishedAt: Date(), signature: "",
                                           keyId: "k1", validUntil: Date().addingTimeInterval(30 * 86_400))
            try? ReportExporter.writePDF(controller.report, detailed: false, publication: sample, to: dir.appendingPathComponent("6-rapport-niveau2.pdf"))
            try? ReportExporter.writeSheet(PublishedReportArchive(report: controller.report, publication: sample), logo: nil,
                                           to: dir.appendingPathComponent("7-fiche-a5.pdf"))
            await publishIfRequested(controller, publisher: publisher, dir: dir)
            NSApp.terminate(nil)
        }
    }

    /// Développement : `--snapshot-publish-key ACK-… --publish-server http://127.0.0.1:8787` publie réellement
    /// le rapport sur le serveur local, puis rend la feuille de confirmation, l'écran Rapport et le PDF de niveau 2.
    private static func publishIfRequested(_ controller: CheckController, publisher: PublishController, dir: URL) async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--snapshot-publish-key"), i + 1 < args.count,
              PublishClient.baseURL != PublishClient.productionBaseURL else { return }
        publisher.licenseKey = args[i + 1]
        await publisher.checkLicense()
        render(PublishSheet(report: controller.report).environmentObject(controller).environmentObject(publisher),
               size: CGSize(width: 640, height: 760), to: dir.appendingPathComponent("8-feuille-publication.png"))
        await publisher.publish(controller.report)
        let report = controller.report
        guard let archive = publisher.published[report.reportID] else {
            try? "\(publisher.state)".write(to: dir.appendingPathComponent("8-echec-publication.txt"), atomically: true, encoding: .utf8)
            return
        }
        try? ReportCoding.encoder().encode(archive).write(to: dir.appendingPathComponent("9-archive.json"))
        try? ReportExporter.writePDF(archive.report, detailed: false, publication: archive.publication, to: dir.appendingPathComponent("9-rapport-publie.pdf"))
        render(ReportScreen().environmentObject(controller).environmentObject(publisher),
               size: CGSize(width: 1200, height: 1100), to: dir.appendingPathComponent("9-ecran-rapport.png"))
    }

    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        hosting.appearance = NSApp.appearance
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
