import SwiftUI
import AmanCore
import AmanDesign
import DiskHealthCore

/// Haut-parleurs (correctifs §6.5), refait après essai réel : un son qui monte du grave à l'aigu (3 s), puis
/// 3 manches de 3 bips (1,65 s) d'un côté tiré au hasard (impossible de réussir sans écouter), puis la netteté.
/// L'image ne s'allume que pendant le son de l'étape 1 ; pendant le quiz elle reste neutre.
struct SpeakerTestView: View {
    let finish: (TestResult) -> Void

    private enum Stage: Equatable { case ready, sweep, quiz(round: Int), quality }

    @State private var stage: Stage = .ready
    @State private var output: AudioDevices.Device?
    @State private var generator = ToneGenerator()
    /// Un son est en cours (boutons de réponse désactivés).
    @State private var playing = false
    /// Silence avant la manche suivante : affiché comme « Écoutez… », boutons désactivés (sinon l'écran
    /// semblait figé, question posée avant le son). Annulé si le test se ferme : aucun bip après coup.
    @State private var pendingRound: DispatchWorkItem?
    private var busy: Bool { playing || pendingRound != nil }
    @State private var sweepProgress = 0.0
    @State private var progressTimer: Timer?
    @State private var quizSides: [ToneGenerator.Side] = []
    @State private var answers: [Bool] = []

    private static let rounds = 3
    /// Silence avant chaque manche (retour Reddit : les sons s'enchaînaient trop vite pour situer le côté).
    private static let pauseBeforeBeeps = 1.2

    var body: some View {
        TestScaffold(title: L("Speakers", "Haut-parleurs"), instruction: instruction) {
            VStack(spacing: 22) {
                outputWarning
                SpeakersPicture(active: stage == .sweep && playing ? .both : nil, hidden: isQuiz)
                    .frame(height: 150)
                stageContent
            }
            .frame(maxWidth: 640)
        } actions: {
            actions
        }
        .onAppear {
            refreshOutput()
            generator.prepare()
        }
        .onDisappear {
            progressTimer?.invalidate()
            pendingRound?.cancel()
            pendingRound = nil
            generator.stop()
        }
    }

    private var isQuiz: Bool { if case .quiz = stage { return true } else { return false } }

    private var instruction: String {
        switch stage {
        case .ready, .sweep:
            return L("Check that the sound comes out of both speakers, clearly, and that you can tell left from right.",
                     "Vérifiez que le son sort des deux haut-parleurs, net, et que vous distinguez la gauche de la droite.")
        case .quiz(let round):
            return L("Round \(round + 1) of \(Self.rounds): where did the beeps come from?", "Manche \(round + 1) sur \(Self.rounds) : d'où venaient les bips ?")
        case .quality:
            return L("Was the sound clear, without crackling or buzzing?", "Le son était-il net, sans grésillement ni vibration ?")
        }
    }

    @ViewBuilder
    private var outputWarning: some View {
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
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .ready:
            NumberedSteps(steps: [
                .init(text: L("Raise the volume to about half.", "Montez le volume à la moitié environ.")),
                .init(text: L("Click Listen: a sound rises from low to high (3 seconds), from both speakers.",
                              "Cliquez sur Écouter : un son monte du grave à l'aigu (3 secondes), sur les deux haut-parleurs.")),
                .init(text: L("Then 3 short beeps, three times: say whether they come from the left, the right or both sides.",
                              "Puis 3 petits bips, trois fois : dites s'ils viennent de gauche, de droite ou des deux côtés."))
            ])
        case .sweep:
            VStack(spacing: 10) {
                Text(L("The sound rises from low to high…", "Le son monte du grave à l'aigu…"))
                    .font(.title3.weight(.medium))
                ProgressView(value: sweepProgress)
                    .tint(AmanPalette.water)
                    .frame(maxWidth: 360)
            }
        case .quiz:
            VStack(spacing: 16) {
                Text(busy ? L("Listen…", "Écoutez…") : L("Where did the beeps come from?", "D'où venaient les bips ?"))
                    .font(.title3.weight(.medium))
                HStack(spacing: 12) {
                    answerButton(L("Left", "Gauche"), .left)
                    answerButton(L("Both Sides", "Des deux côtés"), .both)
                    answerButton(L("Right", "Droite"), .right)
                }
                .controlSize(.large)
                Button(L("I heard nothing", "Je n'ai rien entendu")) { answer(nil) }
                    .buttonStyle(.link)
                    .disabled(busy)
            }
        case .quality:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch stage {
        case .ready:
            Button(L("Listen", "Écouter")) { playSweep() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .sweep:
            EmptyView()
        case .quiz:
            Button(L("Play Again", "Rejouer")) { playQuiz() }
                .disabled(busy)
        case .quality:
            Button(L("Listen Again", "Réécouter")) { playSweep(thenQuiz: false) }
                .disabled(playing)
            Button(L("No, It Crackles", "Non, ça grésille")) { complete(clean: false) }
            Button(L("Yes, It's Clear", "Oui, c'est net")) { complete(clean: true) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func answerButton(_ title: String, _ side: ToneGenerator.Side) -> some View {
        Button(title) { answer(side) }
            .frame(minWidth: 120)
            .disabled(busy)
    }

    private func refreshOutput() {
        output = AudioDevices.defaultDevice(input: false)
    }

    /// Étape 1 : le balayage sur les deux haut-parleurs, avec sa barre de progression ; le quiz suit seul.
    private func playSweep(thenQuiz: Bool = true) {
        refreshOutput()
        if thenQuiz { stage = .sweep }
        playing = true
        sweepProgress = 0
        let started = Date()
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { sweepProgress = min(1, Date().timeIntervalSince(started) / ToneGenerator.Kind.sweep.duration) }
        }
        generator.play(.sweep, side: .both) {
            progressTimer?.invalidate()
            sweepProgress = 1
            playing = false
            if thenQuiz { startQuiz() }
        }
    }

    private func startQuiz() {
        // Les trois réponses proposées sont toutes possibles : « Des deux côtés » n'est pas un piège toujours faux.
        let sides: [ToneGenerator.Side] = [.left, .right, .both]
        quizSides = (0..<Self.rounds).map { _ in sides.randomElement()! }
        answers = []
        stage = .quiz(round: 0)
        playAfterPause()
    }

    /// Un silence avant chaque manche, puis les bips.
    private func playAfterPause() {
        pendingRound?.cancel()
        let item = DispatchWorkItem {
            pendingRound = nil
            playQuiz()
        }
        pendingRound = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseBeforeBeeps, execute: item)
    }

    private func playQuiz() {
        guard case .quiz(let round) = stage, !busy else { return }
        playing = true
        generator.play(.pips, side: quizSides[round]) {
            playing = false
        }
    }

    private func answer(_ side: ToneGenerator.Side?) {
        guard case .quiz(let round) = stage, !busy else { return }
        answers.append(side == quizSides[round])
        if round + 1 < Self.rounds {
            stage = .quiz(round: round + 1)
            playAfterPause()
        } else {
            stage = .quality
        }
    }

    private func complete(clean: Bool) {
        pendingRound?.cancel()
        pendingRound = nil
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
    /// Quiz : aucun haut-parleur allumé, un « ? » au centre (l'image ne doit pas donner la réponse).
    var hidden = false

    var body: some View {
        HStack(spacing: 80) {
            speaker(on: !hidden && (active == .left || active == .both), label: L("Left", "Gauche"), mirrored: true)
            Image(systemName: hidden ? "questionmark.circle" : "laptopcomputer")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.secondary)
            speaker(on: !hidden && (active == .right || active == .both), label: L("Right", "Droite"))
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
