import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

// Tests guidés des capteurs (spec §6.6) : capot, luminosité ambiante, rétroéclairage du clavier.
// Les verdicts viennent de SensorTests (AmanCore).

// MARK: - Capteur du capot

/// Surveille l'état du capot (toutes les 0,25 s), la veille et le réveil, et les écrans externes.
@MainActor
final class LidMonitor: ObservableObject {
    @Published private(set) var observation: LidObservation
    @Published private(set) var externalDisplay = SensorCollector.externalDisplayConnected()
    @Published private(set) var watching = false
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []

    init() {
        observation = LidObservation(stateReadable: SensorCollector.clamshellClosed() != nil)
    }

    func start() {
        stop()
        observation = LidObservation(stateReadable: observation.stateReadable)
        watching = true
        DiagnosticLog.shared.log("lid", "début : état lisible=\(observation.stateReadable) écran externe=\(externalDisplay)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for (name, isSleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.power(isSleep: isSleep, name: note.name.rawValue) }
            })
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        watching = false
    }

    /// Hors test : l'écran externe peut être débranché pendant que la consigne est affichée.
    func refreshDisplays() {
        externalDisplay = SensorCollector.externalDisplayConnected()
    }

    private func poll() {
        refreshDisplays()
        guard let closed = SensorCollector.clamshellClosed() else { return }
        if closed && !observation.sawClosed {
            observation.sawClosed = true
            DiagnosticLog.shared.log("lid", "capot fermé")
        } else if !closed && observation.sawClosed && !observation.sawOpened {
            observation.sawOpened = true
            DiagnosticLog.shared.log("lid", "capot ouvert")
        }
    }

    private func power(isSleep: Bool, name: String) {
        DiagnosticLog.shared.log("lid", name)
        if isSleep {
            observation.slept = true
        } else if observation.slept {
            observation.woke = true
        }
        poll()
    }
}

struct LidTestView: View {
    let finish: (TestResult) -> Void
    @StateObject private var monitor = LidMonitor()
    @State private var asking = false
    @State private var displayTimer: Timer?

    var body: some View {
        let gated = SensorTests.lidNeedsExternalDisplayUnplugged(stateReadable: monitor.observation.stateReadable,
                                                                 externalDisplay: monitor.externalDisplay)
        let detected = SensorTests.lidResult(monitor.observation, screenReacted: nil)
        TestScaffold(title: TestID.lid.title,
                     instruction: L("Click Start, close the lid, wait 5 seconds, then open it again.",
                                    "Cliquez sur Commencer, fermez le capot, attendez 5 secondes, puis rouvrez-le.")) {
            VStack(spacing: 18) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 88, weight: .thin))
                    .foregroundStyle(detected != nil ? .green : AmanPalette.water)
                    .amanPulse(isActive: monitor.watching && detected == nil)
                if gated {
                    Callout(tint: .orange, symbol: "display.2") {
                        Text(L("An external display is connected: with the lid closed, the Mac stays awake and the test would show nothing. Unplug the display to run the test.",
                               "Un écran externe est branché : capot fermé, le Mac reste éveillé et le test ne montrerait rien. Débranchez l'écran pour faire le test."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let detected {
                    StatusLabel(.good, text: detected.summary, font: .headline)
                } else if asking {
                    Text(L("Did the screen turn off when you closed the lid, and back on when you opened it?",
                           "L'écran s'est-il éteint à la fermeture du capot, et rallumé à l'ouverture ?"))
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if monitor.externalDisplay {
                        HintRow(text: L("An external display is connected: the Mac will not go to sleep, the app watches the lid sensor directly.",
                                        "Un écran externe est branché : le Mac ne se mettra pas en veille, l'app surveille directement le capteur du capot."))
                    }
                    HintRow(text: monitor.watching
                            ? L("Waiting for the lid to close and open…", "En attente de la fermeture et de l'ouverture du capot…")
                            : L("Closing the lid puts the Mac to sleep; opening it wakes it up. Nothing else changes.",
                                "Fermer le capot met le Mac en veille ; l'ouvrir le réveille. Rien d'autre ne change."))
                }
            }
            .frame(maxWidth: 560)
        } actions: {
            if gated {
                Button(L("Skip", "Passer")) {
                    finish(.notTested(.lid, reason: L("External display connected", "Écran externe branché")))
                }
            } else if let detected {
                Button(L("Continue", "Continuer")) { finish(detected) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if asking {
                Button(L("No", "Non")) { answer(false) }
                Button(L("Yes", "Oui")) { answer(true) }
                    .buttonStyle(.borderedProminent)
            } else if monitor.watching {
                Button(L("I Closed and Opened the Lid", "J'ai fermé et rouvert le capot")) { asking = true }
            } else {
                Button(L("Start", "Commencer")) { monitor.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { monitor.refreshDisplays() }
            }
        }
        .onDisappear {
            displayTimer?.invalidate()
            monitor.stop()
        }
    }

    private func answer(_ reacted: Bool) {
        if let result = SensorTests.lidResult(monitor.observation, screenReacted: reacted) {
            monitor.stop()
            finish(result)
        }
    }
}

// MARK: - Capteur de luminosité ambiante

struct AmbientLightTestView: View {
    let finish: (TestResult) -> Void

    private enum Phase: Equatable { case ready, covering(Int), asking, measured }
    @State private var phase: Phase = .ready
    @State private var before: Double?
    @State private var lowest: Double?
    @State private var timer: Timer?
    @State private var measured: TestResult?

    /// Durée d'observation : 3 secondes capteur couvert, plus le temps que la luminosité suive.
    private let seconds = 6

    var body: some View {
        TestScaffold(title: TestID.ambientLight.title,
                     instruction: L("Click Start, then cover the sensor next to the camera with your hand for 3 seconds.",
                                    "Cliquez sur Commencer, puis couvrez avec la main le capteur situé près de la caméra pendant 3 secondes.")) {
            VStack(spacing: 18) {
                Image(systemName: phase == .ready ? "sun.max" : "sun.min")
                    .font(.system(size: 88, weight: .thin))
                    .foregroundStyle(phase == .measured ? .green : AmanPalette.water)
                    .amanPulse(isActive: { if case .covering = phase { return true } else { return false } }())
                switch phase {
                case .ready:
                    HintRow(text: L("Automatic brightness must be on: System Settings › Displays › “Automatically adjust brightness”.",
                                    "La luminosité automatique doit être activée : Réglages Système › Moniteurs › « Régler la luminosité automatiquement »."))
                case .covering(let left):
                    Text(L("Keep the sensor covered… \(left) s", "Gardez le capteur couvert… \(left) s"))
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                case .asking:
                    Text(L("Did the screen (or the keyboard backlight) change brightness while the sensor was covered?",
                           "La luminosité de l'écran (ou du rétroéclairage du clavier) a-t-elle changé pendant que le capteur était couvert ?"))
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                case .measured:
                    StatusLabel(.good, text: measured?.summary ?? "", font: .headline)
                }
            }
            .frame(maxWidth: 560)
        } actions: {
            switch phase {
            case .ready:
                Button(L("Start", "Commencer")) { start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .covering:
                EmptyView()
            case .asking:
                Button(L("Automatic Brightness Is Off", "La luminosité automatique est désactivée")) { answer(.automaticBrightnessOff) }
                Button(L("Nothing Changed", "Rien n'a changé")) { answer(.noChange) }
                Button(L("Brightness Changed", "La luminosité a changé")) { answer(.changed) }
                    .buttonStyle(.borderedProminent)
            case .measured:
                Button(L("Continue", "Continuer")) { if let measured { finish(measured) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        before = SensorCollector.builtInBrightness()
        lowest = before
        DiagnosticLog.shared.log("ambient", "luminosité avant : \(before.map { String(format: "%.3f", $0) } ?? "illisible")")
        var ticks = 0
        phase = .covering(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
            MainActor.assumeIsolated {
                ticks += 1
                if let level = SensorCollector.builtInBrightness() { lowest = min(lowest ?? level, level) }
                let left = seconds - ticks / 5
                if left <= 0 {
                    t.invalidate()
                    DiagnosticLog.shared.log("ambient", "luminosité la plus basse : \(lowest.map { String(format: "%.3f", $0) } ?? "illisible")")
                    if let result = SensorTests.ambientResult(brightnessBefore: before, brightnessLowest: lowest, answer: nil) {
                        measured = result
                        phase = .measured
                    } else {
                        phase = .asking
                    }
                } else {
                    phase = .covering(left)
                }
            }
        }
    }

    private func answer(_ answer: SensorTests.AmbientAnswer) {
        if let result = SensorTests.ambientResult(brightnessBefore: before, brightnessLowest: lowest, answer: answer) {
            finish(result)
        }
    }
}

// MARK: - Rétroéclairage du clavier

struct KeyboardBacklightTestView: View {
    let profile: DeviceProfile
    let finish: (TestResult) -> Void

    var body: some View {
        TestScaffold(title: TestID.keyboardBacklight.title,
                     instruction: L("Turn the keyboard backlight up, then look at the keys.",
                                    "Augmentez le rétroéclairage du clavier, puis regardez les touches.")) {
            VStack(spacing: 18) {
                Image(systemName: "light.max")
                    .font(.system(size: 88, weight: .thin))
                    .foregroundStyle(AmanPalette.water)
                VStack(alignment: .leading, spacing: 10) {
                    HintRow(text: profile.hasTouchBar
                            ? L("On the Touch Bar, expand the Control Strip and use the keyboard brightness buttons, or open Control Centre › Keyboard Brightness.",
                                "Dans la Touch Bar, développez la Control Strip et utilisez les boutons de luminosité du clavier, ou ouvrez le Centre de contrôle › Luminosité du clavier.")
                            : L("Open Control Centre in the menu bar, then Keyboard Brightness, and drag it up.",
                                "Ouvrez le Centre de contrôle dans la barre des menus, puis Luminosité du clavier, et montez le curseur."))
                    HintRow(text: L("In a bright room, shade the keys with your hand. If the backlight stays off, turn off “Adjust keyboard brightness in low light” in System Settings › Keyboard.",
                                    "Dans une pièce claire, faites de l'ombre aux touches avec la main. Si le rétroéclairage reste éteint, désactivez « Régler la luminosité du clavier en cas de faible éclairage » dans Réglages Système › Clavier."))
                }
                Text(L("Do all the keys light up evenly?", "Toutes les touches s'éclairent-elles de façon régulière ?"))
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        } actions: {
            Button(L("No", "Non")) { finish(SensorTests.keyboardBacklightResult(works: false)) }
            Button(L("Yes", "Oui")) { finish(SensorTests.keyboardBacklightResult(works: true)) }
                .buttonStyle(.borderedProminent)
        }
    }
}
