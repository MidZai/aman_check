import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Température du processeur et vitesse des ventilateurs, en direct (toutes les 2 s) : lecture du SMC hors du
/// fil principal, sur sa propre connexion (le test de performance garde la sienne). S'arrête quand l'écran
/// disparaît ; rien n'est affiché si le SMC ne se lit pas.
@MainActor
final class LiveSensors: ObservableObject {
    @Published private(set) var temperature: Double?
    @Published private(set) var fans: [Double?] = []
    @Published private(set) var readable = false

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.aman.check.live-sensors")
    /// Utilisée uniquement sur `queue`.
    private nonisolated(unsafe) var session: SensorCollector.Session?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session == nil { self.session = SensorCollector.Session() }
            let temperature = self.session?.cpuTemperature()
            let fans = self.session?.fanSpeeds() ?? []
            DispatchQueue.main.async {
                self.temperature = temperature
                self.fans = fans
                self.readable = temperature != nil || fans.contains { $0 != nil }
            }
        }
    }
}

/// Bandeau « Processeur 62 °C · Ventilateurs 2 972 tr/min, 2 769 tr/min · en direct ».
struct LiveSensorsStrip: View {
    let hasFan: Bool?
    @StateObject private var live = LiveSensors()

    var body: some View {
        // Toujours une vue présente : `onAppear` ne se déclenche pas sur un `Group` vide, et la lecture ne
        // démarrerait jamais (constaté : bandeau absent).
        ZStack {
            Color.clear.frame(width: 1, height: 1)
            if live.readable {
                HStack(spacing: 18) {
                    if let t = live.temperature {
                        Label {
                            Text(L("Processor", "Processeur") + " ") + Text(Formatters.temperature(Int(t.rounded()))).bold()
                        } icon: {
                            Image(systemName: "thermometer.medium").foregroundStyle(t >= SensorAnalysis.restingTemperatureWatch ? Color.orange : AmanPalette.water)
                        }
                    }
                    if hasFan != false, !live.fans.isEmpty {
                        Label {
                            Text(L("Fans", "Ventilateurs") + " ")
                                + Text(live.fans.map { $0.map(SensorAnalysis.fanSpeedText) ?? "—" }.joined(separator: ", ")).bold()
                        } icon: {
                            Image(systemName: "fan").foregroundStyle(AmanPalette.water)
                        }
                    } else if hasFan == false {
                        Label(L("No fan on this model", "Pas de ventilateur sur ce modèle"), systemImage: "fan.slash")
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text(L("live", "en direct"))
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1), in: Capsule())
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }
}
