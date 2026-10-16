import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Haut-parleurs : sortie vérifiée, son grave, balayage, gauche/droite, puis quiz au hasard
/// pour qu'on ne puisse pas valider sans écouter (correctifs §6.5).
struct SpeakerTestView: View {
    let finish: (TestResult) -> Void

    private enum Stage: Equatable { case check, demo, quiz(round: Int), quality }

    @State private var stage: Stage = .check
    @State private var output: AudioDevices.Device?
    @State private var generator = ToneGenerator()
    @State private var playing: ToneGenerator.Side?
    @State private var demoDone = false
    @State private var quizSides: [ToneGenerator.Side] = []
    @State private var answers: [Bool] = []
    @State private var quizPlayed = false

    private static let rounds = 3

    var body: some View {
        TestScaffold(title: L("Speakers", "Haut-parleurs"), instruction: instruction) {
            VStack(spacing: 24) {
                if let output, !output.isInternalSpeakers {
                    Callout(tint: .orange, symbol: "speaker.slash") {
                        Text(L("The current sound output is “\(output.name)”. Switch to this Mac's speakers.",
                               "La sortie audio actuelle est « \(output.name) ». Passez sur les haut-parleurs du Mac."))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L("Open Sound Settings", "Ouvrir les réglages Son")) { AudioDevices.openSoundSettings() }
                            Button(L("Check Again", "Vérifier à nouveau")) { refreshOutput() }
                        }
                    }
                } else if let output, output.isMuted == true || (output.volume ?? 1) < 0.25 {
                    Callout(tint: .orange, symbol: "speaker.wave.1") {
                        Text(output.isMuted == true
                             ? L("Sound is muted. Turn it on and raise the volume to about half.", "Le son est coupé. Réactivez-le et montez le volume à la moitié environ.")
                             : L("The volume is low. Raise it to about half.", "Le volume est faible. Montez-le à la moitié environ."))
                        Button(L("Check Again", "Vérifier à nouveau")) { refreshOutput() }
                    }
                }
                SpeakersPicture(active: playing)
                    .frame(height: 170)
                stageContent
                if case .quiz = stage {
                    HintRow(text: L("The side is drawn at random each round: the test cannot be passed without listening. The picture stays neutral on purpose.",
                                    "Le côté est tiré au hasard à chaque manche : impossible de réussir sans écouter. L'image reste neutre exprès."))
                } else if stage != .quality {
                    HintRow(text: L("The low tone reveals buzzing or rattling; the sweep checks every frequency. On Macs with several speakers, left/right is approximate.",
                                    "Le son grave révèle grésillements et vibrations ; le balayage vérifie toutes les fréquences. Sur les Mac à plusieurs haut-parleurs, gauche/droite reste approximatif."))
                }
            }
            .frame(maxWidth: 640)
        } actions: {
            actions
        }
        .onAppear { refreshOutput() }
        .onDisappear { generator.stop() }
    }

    private var instruction: String {
        switch stage {
        case .check, .demo:
            return L("Raise the volume to about half. You will hear a low tone and a sweep (4 seconds), then 3 short beeps: say where each one came from.",
                     "Montez le volume à la moitié environ. Vous allez entendre un son grave et un balayage (4 secondes), puis 3 bips courts : dites d'où vient chacun.")
        case .quiz(let round):
            return L("Round \(round + 1) of \(Self.rounds): where did you hear the sound?", "Manche \(round + 1) sur \(Self.rounds) : de quel côté avez-vous entendu le son ?")
        case .quality:
            return L("Was the sound clear, without crackling or buzzing?", "Le son était-il net, sans grésillement ni vibration ?")
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .check, .demo:
            EmptyView()
        case .quiz:
            HStack(spacing: 12) {
                answerButton(L("Left", "Gauche"), .left)
                answerButton(L("Right", "Droite"), .right)
                answerButton(L("Both", "Les deux"), .both)
                Button(L("I heard nothing", "Je n'ai rien entendu")) { answer(nil) }
                    .disabled(!quizPlayed || playing != nil)
            }
            .controlSize(.large)
        case .quality:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch stage {
        case .check, .demo:
            Button(L("Play the Sounds", "Jouer les sons")) { runDemo() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(playing != nil)
        case .quiz:
            Button(L("Play Again", "Rejouer")) { playQuiz() }
                .disabled(playing != nil)
        case .quality:
            Button(L("No, It Crackles", "Non, ça grésille")) { complete(clean: false) }
            Button(L("Yes, It's Clear", "Oui, c'est net")) { complete(clean: true) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func answerButton(_ title: String, _ side: ToneGenerator.Side) -> some View {
        Button(title) { answer(side) }
            .disabled(!quizPlayed || playing != nil)
    }

    private func refreshOutput() {
        output = AudioDevices.defaultDevice(input: false)
    }

    /// Son grave puis balayage (4 s), et le quiz enchaîne de lui-même : plus de démonstration gauche/droite
    /// ni de clic « Jouer » à chaque manche (le test prenait trop de temps).
    private func runDemo() {
        refreshOutput()
        stage = .demo
        demoDone = false
        let sequence: [(ToneGenerator.Kind, ToneGenerator.Side)] = [(.lowTone, .both), (.sweep, .both)]
        playSequence(sequence[...]) {
            demoDone = true
            startQuiz()
        }
    }

    private func playSequence(_ items: ArraySlice<(ToneGenerator.Kind, ToneGenerator.Side)>, done: @escaping () -> Void) {
        guard let (kind, side) = items.first else {
            playing = nil
            done()
            return
        }
        playing = side
        generator.play(kind, side: side) {
            playSequence(items.dropFirst(), done: done)
        }
    }

    private func startQuiz() {
        // Les trois réponses proposées sont toutes possibles : « Les deux » n'est pas un piège toujours faux.
        let sides: [ToneGenerator.Side] = [.left, .right, .both]
        quizSides = (0..<Self.rounds).map { _ in sides.randomElement()! }
        answers = []
        quizPlayed = false
        stage = .quiz(round: 0)
        playQuiz()
    }

    private func playQuiz() {
        guard case .quiz(let round) = stage else { return }
        // Pas d'animation pendant le quiz : la réponse ne doit pas se lire à l'écran.
        playing = .both
        generator.play(.beep, side: quizSides[round]) {
            playing = nil
            quizPlayed = true
        }
    }

    private func answer(_ side: ToneGenerator.Side?) {
        guard case .quiz(let round) = stage else { return }
        answers.append(side == quizSides[round])
        quizPlayed = false
        if round + 1 < Self.rounds {
            stage = .quiz(round: round + 1)
            // Petit silence pour que le bip suivant ne se confonde pas avec le clic.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { playQuiz() }
        } else {
            stage = .quality
        }
    }

    private func complete(clean: Bool) {
        generator.stop()
        // Une sortie externe ne dit rien des haut-parleurs du Mac : non testé, à refaire sans le périphérique.
        if let output, !output.isBuiltIn {
            finish(TestResult.notTested(.speakers, reason: AudioDeviceText.externalDeviceReason))
            return
        }
        let correct = answers.filter { $0 }.count
        let summary = L("Side identified \(correct) times out of \(Self.rounds)", "Côté identifié \(correct) fois sur \(Self.rounds)")
            + " · " + (clean ? L("clear sound", "son net") : L("crackling reported", "grésillement signalé"))
        var details = [summary]
        // Catégorie du périphérique seulement, jamais son nom.
        if let output { details.append(L("Output: \(AudioDeviceText.category(isBuiltIn: output.isBuiltIn, input: false))", "Sortie : \(AudioDeviceText.category(isBuiltIn: output.isBuiltIn, input: false))")) }
        details.append(L("Left/right is an approximation on Macs with several speakers.", "Gauche/droite est une approximation sur les Mac à plusieurs haut-parleurs."))
        if correct == Self.rounds && clean {
            finish(TestResult(test: .speakers, outcome: .passed, provenance: .userObserved, summary: summary, details: details))
        } else {
            finish(TestResult(test: .speakers, outcome: .failed, status: clean ? .watch : .problem, provenance: .userObserved,
                              summary: summary, details: details))
        }
    }
}

/// Deux haut-parleurs qui s'allument selon le côté joué.
private struct SpeakersPicture: View {
    let active: ToneGenerator.Side?

    var body: some View {
        HStack(spacing: 80) {
            speaker(on: active == .left || active == .both, label: L("Left", "Gauche"), mirrored: true)
            Image(systemName: "laptopcomputer")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.secondary)
            speaker(on: active == .right || active == .both, label: L("Right", "Droite"))
        }
    }

    private func speaker(on: Bool, label: String, mirrored: Bool = false) -> some View {
        VStack(spacing: 10) {
            Image(systemName: on ? "speaker.wave.3.fill" : "speaker.fill")
                .font(.system(size: 44))
                .foregroundStyle(on ? AmanPalette.water : Color.secondary.opacity(0.5))
                .amanVariableColor(isActive: on)
                .frame(width: 90, height: 70)
                .scaleEffect(x: mirrored ? -1 : 1)
            Text(label).foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.15), value: on)
    }
}
