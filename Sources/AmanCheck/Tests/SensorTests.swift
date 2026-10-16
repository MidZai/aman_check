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
                    HintRow(text: L("When you open it again, the Mac may ask for your password or Touch ID: unlock it, this screen will be waiting.",
                                    "À la réouverture, le Mac peut demander votre mot de passe ou Touch ID : déverrouillez-le, cet écran vous attend."))
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

// MARK: - Aides communes

/// Ouvre une page de Réglages Système (lecture seule pour l'app : la personne fait le réglage elle-même).
enum SystemSettingsPage {
    case displays, keyboard

    /// Adresses de macOS 13 et plus, puis celles des anciennes Préférences Système en repli.
    private var urls: [String] {
        switch self {
        case .displays: return ["x-apple.systempreferences:com.apple.Displays-Settings.extension",
                                "x-apple.systempreferences:com.apple.preference.displays"]
        case .keyboard: return ["x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                                "x-apple.systempreferences:com.apple.preference.keyboard"]
        }
    }

    func open() {
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

/// Étapes numérotées d'une consigne (1, 2, 3), avec un bouton facultatif sous une étape.
struct NumberedSteps: View {
    struct Step: Identifiable {
        let id = UUID()
        let text: String
        var buttonTitle: String? = nil
        var action: (() -> Void)? = nil
    }
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(AmanPalette.water, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.text).fixedSize(horizontal: false, vertical: true)
                        if let title = step.buttonTitle, let action = step.action {
                            Button(title, action: action).controlSize(.regular)
                        }
                    }
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Le haut de l'écran du Mac : la caméra au centre et, juste à côté, le capteur de luminosité.
/// La zone à couvrir est entourée ; la main descend dessus pendant le test.
struct TopOfScreenDiagram: View {
    let covering: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Cadre et dalle.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.16))
                .frame(width: 360, height: 150)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.52, blue: 0.78), Color(red: 0.42, green: 0.66, blue: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(covering ? 0.55 : 1)
                .frame(width: 336, height: 118)
                .offset(y: 24)
            // Caméra.
            Circle().fill(Color.black)
                .overlay(Circle().strokeBorder(Color(white: 0.35), lineWidth: 1))
                .frame(width: 9, height: 9)
                .offset(y: 8)
            // Zone à couvrir.
            Capsule()
                .strokeBorder(AmanPalette.water, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                .frame(width: 120, height: 34)
                .offset(y: -4)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color(red: 0.93, green: 0.78, blue: 0.64))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .offset(y: covering ? -10 : -78)
                .animation(.easeInOut(duration: 0.5), value: covering)
        }
        .frame(width: 360, height: 150)
        .padding(.top, 70)
        .overlay(alignment: .topTrailing) {
            Text(L("camera and sensor", "caméra et capteur"))
                .font(.caption.weight(.medium))
                .foregroundStyle(AmanPalette.water)
                .offset(x: -6, y: 56)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("The light sensor is at the top of the screen, next to the camera.",
                              "Le capteur de luminosité est en haut de l'écran, à côté de la caméra."))
    }
}

// MARK: - Capteur de luminosité ambiante

struct AmbientLightTestView: View {
    let profile: DeviceProfile
    let finish: (TestResult) -> Void

    private enum Phase: Equatable { case ready, covering(Int), asking, measured }
    @State private var phase: Phase = .ready
    @State private var before: Double?
    @State private var lowest: Double?
    @State private var current: Double?
    @State private var timer: Timer?
    @State private var measured: TestResult?

    /// Main posée 5 s : la luminosité automatique met 2 à 3 s à réagir.
    private let seconds = 5

    private var isCovering: Bool { if case .covering = phase { return true } else { return false } }

    var body: some View {
        TestScaffold(title: TestID.ambientLight.title,
                     instruction: L("The sensor is hidden at the top of the screen, next to the camera. No need to find it: your hand covers it.",
                                    "Le capteur est caché en haut de l'écran, à côté de la caméra. Inutile de le chercher : votre main le couvre.")) {
            VStack(spacing: 22) {
                TopOfScreenDiagram(covering: isCovering)
                switch phase {
                case .ready:
                    NumberedSteps(steps: [
                        .init(text: L("Check that automatic brightness is on: “Automatically adjust brightness” in the display settings.",
                                      "Vérifiez que la luminosité automatique est activée : « Régler la luminosité automatiquement » dans les réglages des moniteurs."),
                              buttonTitle: L("Open Display Settings", "Ouvrir les réglages des moniteurs"),
                              action: { SystemSettingsPage.displays.open() }),
                        .init(text: L("Click Start, then lay your hand flat over the top middle of the screen, over the camera.",
                                      "Cliquez sur Commencer, puis posez la main à plat en haut et au milieu de l'écran, sur la caméra.")),
                        .init(text: L("Keep it there until the countdown ends, and watch the screen: it should dim.",
                                      "Gardez-la jusqu'à la fin du compte à rebours en regardant l'écran : il doit s'assombrir."))
                    ])
                    .frame(maxWidth: 560)
                case .covering(let left):
                    VStack(spacing: 8) {
                        Text(L("Cover the top of the screen now… \(left)", "Couvrez le haut de l'écran maintenant… \(left)"))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        if let before, let current {
                            Text(L("Screen brightness: \(Self.percent(before)) → \(Self.percent(current))",
                                   "Luminosité de l'écran : \(Self.percent(before)) → \(Self.percent(current))"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                case .asking:
                    VStack(spacing: 8) {
                        Text(L("You can take your hand away.", "Vous pouvez retirer la main."))
                            .foregroundStyle(.secondary)
                        Text(L("Did the screen (or the keyboard backlight) get darker while your hand was there?",
                               "L'écran (ou le rétroéclairage du clavier) s'est-il assombri pendant que votre main était posée ?"))
                            .font(.title3.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 560)
                case .measured:
                    VStack(spacing: 8) {
                        Text(L("You can take your hand away.", "Vous pouvez retirer la main."))
                            .foregroundStyle(.secondary)
                        StatusLabel(.good, text: measured?.summary ?? "", font: .headline)
                    }
                }
            }
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
                Button(L("Try Again", "Réessayer")) { phase = .ready }
                Button(L("No, Nothing Changed", "Non, rien n'a changé")) { answer(.noChange) }
                Button(L("Yes, It Got Darker", "Oui, il s'est assombri")) { answer(.changed) }
                    .buttonStyle(.borderedProminent)
            case .measured:
                Button(L("Continue", "Continuer")) { if let measured { finish(measured) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private static func percent(_ value: Double) -> String { Formatters.percentage((value * 100).rounded()) }

    private func start() {
        before = SensorCollector.builtInBrightness()
        lowest = before
        current = before
        DiagnosticLog.shared.log("ambient", "luminosité avant : \(before.map { String(format: "%.3f", $0) } ?? "illisible")")
        var ticks = 0
        phase = .covering(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
            MainActor.assumeIsolated {
                ticks += 1
                if let level = SensorCollector.builtInBrightness() {
                    current = level
                    lowest = min(lowest ?? level, level)
                }
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
                     instruction: L("Light up the keyboard, then check that every key lights up.",
                                    "Allumez l'éclairage du clavier, puis vérifiez que chaque touche s'éclaire.")) {
            VStack(spacing: 22) {
                Image(systemName: "keyboard")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(AmanPalette.water)
                NumberedSteps(steps: lightUpSteps + [
                    .init(text: L("Shade the keys with your hand (in a bright room the light is hard to see): every key should light up, with no dark key or dark area.",
                                  "Faites de l'ombre aux touches avec la main (dans une pièce claire, la lumière se voit mal) : chaque touche doit s'éclairer, sans touche ni zone sombre.")),
                    .init(text: L("Still off? The Mac may turn it off by itself in a bright room: turn off “Adjust keyboard brightness in low light”.",
                                  "Toujours éteint ? Le Mac peut l'éteindre de lui-même dans une pièce claire : désactivez « Régler la luminosité du clavier en cas de faible éclairage »."),
                          buttonTitle: L("Open Keyboard Settings", "Ouvrir les réglages du clavier"),
                          action: { SystemSettingsPage.keyboard.open() })
                ])
                .frame(maxWidth: 560)
                Text(L("Do all the keys light up evenly?", "Toutes les touches s'éclairent-elles de façon régulière ?"))
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        } actions: {
            Button(L("No", "Non")) { finish(SensorTests.keyboardBacklightResult(works: false)) }
            Button(L("Yes", "Oui")) { finish(SensorTests.keyboardBacklightResult(works: true)) }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Comment allumer l'éclairage : par la Touch Bar quand il y en a une, sinon par le Centre de contrôle.
    private var lightUpSteps: [NumberedSteps.Step] {
        if profile.hasTouchBar {
            return [.init(text: L("On the Touch Bar, tap the small arrow ‹ on the right, then the keyboard brightness button (a keyboard with rays) until the keys light up.",
                                  "Dans la Touch Bar, touchez la petite flèche ‹ à droite, puis le bouton de luminosité du clavier (un clavier avec des rayons) jusqu'à ce que les touches s'éclairent."))]
        }
        return [.init(text: L("Click Control Centre at the top right of the screen (the icon with two small switches), then Keyboard Brightness, and drag the slider all the way up.",
                              "Cliquez sur le Centre de contrôle en haut à droite de l'écran (l'icône à deux petits interrupteurs), puis sur Luminosité du clavier, et poussez le curseur à fond."))]
    }
}
