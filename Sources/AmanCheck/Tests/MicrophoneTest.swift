import SwiftUI
import AVFoundation
import AmanCore
import AmanDesign
import DiskHealthCore

/// Micro : niveau en direct (mesuré) + enregistrement de 3 s puis relecture (constaté).
@MainActor
final class MicrophoneModel: ObservableObject {
    enum Permission { case unknown, granted, denied }

    @Published var permission: Permission = .unknown
    @Published var level: Float = 0          // 0…1
    @Published var peakDB: Float = -160
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var hasRecording = false
    @Published var input: AudioDevices.Device?
    @Published var error: String?

    /// Au-dessus de ce niveau, on considère qu'un son a été capté (voix ou tapotement).
    static let signalThresholdDB: Float = -40

    private let engine = AVAudioEngine()
    private let playbackEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var recorded: [AVAudioPCMBuffer] = []
    private var recordFormat: AVAudioFormat?

    var signalDetected: Bool { peakDB > Self.signalThresholdDB }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permission = .granted
        case .notDetermined: permission = await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        default: permission = .denied
        }
        DiagnosticLog.shared.log("micro", "autorisation : \(permission)")
        guard permission == .granted else { return }
        input = AudioDevices.defaultDevice(input: true)
        startEngine()
    }

    private func startEngine() {
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            error = L("No microphone input available.", "Aucune entrée micro disponible.")
            return
        }
        recordFormat = format
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let db = Self.decibels(buffer)
            let copy = buffer.copy() as? AVAudioPCMBuffer
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = max(0, min(1, (db + 60) / 60))
                self.peakDB = max(self.peakDB, db)
                if self.isRecording, let copy { self.recorded.append(copy) }
            }
        }
        do {
            try engine.start()
            DiagnosticLog.shared.log("micro", "moteur démarré · \(format.sampleRate) Hz, \(format.channelCount) canaux")
        } catch {
            self.error = L("The microphone could not be started.", "Le micro n'a pas pu démarrer.")
            DiagnosticLog.shared.log("micro", "échec du démarrage : \(error)")
        }
    }

    nonisolated static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = sqrt(sum / Float(n))
        return rms > 0 ? 20 * log10(rms) : -160
    }

    func recordAndPlay() {
        guard !isRecording, !isPlaying else { return }
        recorded = []
        isRecording = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isRecording = false
            self?.playBack()
        }
    }

    private func playBack() {
        // L'enregistrement a été tenté : les boutons de réponse se débloquent même si rien n'a été capté,
        // sinon un micro muet laisserait le test sans issue.
        hasRecording = true
        guard let format = recordFormat, !recorded.isEmpty else {
            error = L("Nothing was recorded: the microphone sent no sound for 3 seconds.",
                      "Rien n'a été enregistré : le micro n'a transmis aucun son pendant 3 secondes.")
            DiagnosticLog.shared.log("micro", "enregistrement vide")
            return
        }
        error = nil
        if playbackEngine.attachedNodes.contains(player) == false {
            playbackEngine.attach(player)
            playbackEngine.connect(player, to: playbackEngine.mainMixerNode, format: format)
        }
        do { try playbackEngine.start() } catch {
            DiagnosticLog.shared.log("micro", "relecture impossible : \(error)")
            return
        }
        isPlaying = true
        for (index, buffer) in recorded.enumerated() {
            let isLast = index == recorded.count - 1
            player.scheduleBuffer(buffer) { [weak self] in
                if isLast { DispatchQueue.main.async { self?.isPlaying = false } }
            }
        }
        player.play()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        player.stop()
        playbackEngine.stop()
    }
}

struct MicrophoneTestView: View {
    let finish: (TestResult) -> Void
    @StateObject private var model = MicrophoneModel()

    var body: some View {
        TestScaffold(title: L("Microphone", "Micro"),
                     instruction: L("Speak or tap near the Mac: the gauge should move. Then record 3 seconds and listen to yourself.",
                                    "Parlez ou tapotez près du Mac : la jauge doit bouger. Enregistrez ensuite 3 secondes pour vous réécouter.")) {
            VStack(spacing: 24) {
                switch model.permission {
                case .denied:
                    PermissionDeniedView(subject: L("the microphone", "au micro"), pane: "Privacy_Microphone")
                case .unknown:
                    ProgressView()
                case .granted:
                    if let input = model.input, !input.isBuiltIn {
                        Callout(tint: .orange, symbol: "mic.slash") {
                            Text(L("The current input is “\(input.name)”, not this Mac's microphone. Change it in Sound settings.",
                                   "L'entrée actuelle est « \(input.name) », pas le micro du Mac. Changez-la dans les réglages Son."))
                            Button(L("Open Sound Settings", "Ouvrir les réglages Son")) { AudioDevices.openSoundSettings() }
                        }
                    }
                    if let error = model.error {
                        Callout(tint: .red, symbol: "exclamationmark.triangle") { Text(error) }
                    }
                    LevelMeter(level: model.level)
                        .frame(height: 26)
                    Label(model.signalDetected ? L("Sound picked up", "Son capté") : L("Waiting for a sound…", "En attente d'un son…"),
                          systemImage: model.signalDetected ? "checkmark.circle.fill" : "waveform")
                        .foregroundStyle(model.signalDetected ? Color.green : Color.secondary)
                        .font(.headline)
                    Button {
                        model.recordAndPlay()
                    } label: {
                        Label(model.isRecording ? L("Recording…", "Enregistrement…")
                              : (model.isPlaying ? L("Playing back…", "Relecture…") : L("Record 3 Seconds and Play Back", "Enregistrer 3 secondes et réécouter")),
                              systemImage: model.isRecording ? "record.circle" : "play.circle")
                    }
                    .controlSize(.large)
                    .disabled(model.isRecording || model.isPlaying)
                    HintRow(text: L("The gauge must rise when you speak (measured by the app). The 3-second playback lets you judge the quality yourself. With a high volume you may hear an echo: this is normal.",
                                    "La jauge doit monter quand vous parlez (mesuré par l'app). La relecture de 3 secondes vous permet de juger la qualité vous-même. Avec un volume fort, un écho est possible : c'est normal."))
                }
            }
            .frame(maxWidth: 600)
        } actions: {
            if model.permission == .denied {
                Button(L("Skip", "Passer")) {
                    finish(.notTested(.microphone, reason: L("Microphone access refused", "Accès au micro refusé")))
                }
            } else {
                Button(L("I Can't Hear Myself", "Je ne m'entends pas")) { complete(heard: false) }
                    .disabled(!model.hasRecording || model.isPlaying)
                Button(L("I Can Hear Myself Clearly", "Je m'entends bien")) { complete(heard: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasRecording || model.isPlaying)
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private func complete(heard: Bool) {
        model.stop()
        let measured = model.signalDetected
        let peak = Int(model.peakDB.rounded())
        let summary = (measured ? L("Sound picked up", "Son capté") : L("No sound picked up", "Aucun son capté"))
            + " · " + (heard ? L("playback clear", "relecture nette") : L("playback not heard", "relecture non entendue"))
        let details = [L("Peak level: \(peak) dBFS", "Niveau maximal : \(peak) dBFS"), model.input.map { L("Input: \($0.name)", "Entrée : \($0.name)") } ?? ""]
            .filter { !$0.isEmpty }
        if measured && heard {
            finish(TestResult(test: .microphone, outcome: .passed, provenance: .measuredAuto, summary: summary, details: details))
        } else {
            finish(TestResult(test: .microphone, outcome: .failed, status: measured ? .watch : .problem,
                              provenance: measured ? .userObserved : .measuredAuto, summary: summary, details: details))
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [AmanPalette.water, AmanPalette.water, AmanPalette.orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .accessibilityLabel(L("Microphone level", "Niveau du micro"))
        .accessibilityValue("\(Int(level * 100)) %")
    }
}

/// Refus d'autorisation : test « Non testé », jamais « Échoué », avec un accès direct aux réglages.
struct PermissionDeniedView: View {
    /// « the microphone » / « au micro », « the camera » / « à la caméra ».
    let subject: String
    let pane: String

    var body: some View {
        Callout(tint: .blue, symbol: "lock") {
            Text(L("Access to \(subject) was refused. The test will be marked “Not tested”, not “Failed”.",
                   "L'accès \(subject) a été refusé. Le test sera noté « Non testé », pas « Échoué »."))
                .fixedSize(horizontal: false, vertical: true)
            Text(L("To test it, allow Aman Check in System Settings > Privacy & Security, then reopen the app.",
                   "Pour le tester, autorisez Aman Check dans Réglages Système > Confidentialité et sécurité, puis rouvrez l'app."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Open Privacy Settings", "Ouvrir les réglages de confidentialité")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
