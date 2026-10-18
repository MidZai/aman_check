import Foundation
import AVFoundation
import CoreAudio
import AmanCore
import AppKit

/// Périphériques audio par défaut via Core Audio (correctifs §6.5).
enum AudioDevices {
    struct Device {
        let id: AudioDeviceID
        let name: String
        let isBuiltIn: Bool
        /// Source de données du périphérique intégré : 'ispk' haut-parleurs, 'hdpn' casque. `nil` si inconnue.
        let dataSource: UInt32?
        let volume: Float?
        let isMuted: Bool?

        var isInternalSpeakers: Bool { isBuiltIn && dataSource != fourCC("hdpn") }
        var isHeadphones: Bool { isBuiltIn && dataSource == fourCC("hdpn") }
    }

    static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func defaultDevice(input: Bool) -> Device? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return nil }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let transport: UInt32? = read(deviceID, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal)
        let source: UInt32? = read(deviceID, kAudioDevicePropertyDataSource, scope)
        let volume: Float32? = read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        let mute: UInt32? = read(deviceID, kAudioDevicePropertyMute, scope)
        let device = Device(id: deviceID, name: name(deviceID) ?? "?", isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
                            dataSource: source, volume: volume, isMuted: mute.map { $0 != 0 })
        DiagnosticLog.shared.log("audio", "\(input ? "entrée" : "sortie") : \(device.name) intégré=\(device.isBuiltIn) source=\(source.map { String(format: "%08X", $0) } ?? "-") volume=\(volume.map { String($0) } ?? "-") muet=\(mute.map { String($0) } ?? "-")")
        return device
    }

    /// Volume et sourdine de la sortie par défaut, sans écrire dans le journal (relevé plusieurs fois par seconde).
    static func outputLevel() -> (volume: Float?, muted: Bool?) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return (nil, nil) }
        let volume: Float32? = read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        let mute: UInt32? = read(deviceID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        return (volume, mute.map { $0 != 0 })
    }

    private static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Générateur de sons stéréo déterministe : un seul canal porte le signal, l'autre est silencieux
/// (indépendant du panoramique). Le lecteur et le moteur sont conservés tant que le test existe
/// (un lecteur désalloué juste après `play()` est une cause classique de « pas de son »).
///
/// Sons choisis pour les haut-parleurs d'un portable : rien sous 250 Hz (un son grave à 110 Hz ne sortait
/// presque pas, la personne entendait « un son, puis rien »). Fin d'un son = son réellement joué : signal
/// `.dataPlayedBack` de macOS, ou position de lecture du lecteur arrivée au bout (le signal a manqué au moins
/// une fois en essai réel, l'écran restait figé plusieurs secondes). Un garde-fou rend la main en dernier recours.
@MainActor
final class ToneGenerator {
    enum Side { case left, right, both }
    enum Kind {
        /// Balayage 250 Hz → 8 kHz, 3 s : vérifie toute la plage et révèle grésillements et vibrations.
        case sweep
        /// Trois bips de 0,35 s séparés de 0,3 s (1,65 s). Retour Reddit : des bips de 0,12 s à 1 kHz pur se
        /// situaient très mal à gauche ou à droite. Un son riche en aigus (harmoniques jusqu'à 6 kHz) se situe
        /// bien mieux : l'oreille compare surtout le niveau des aigus entre les deux côtés.
        case pips

        var duration: Double {
            switch self {
            case .sweep: return 3
            case .pips: return 1.65
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double = 48_000
    /// Numéro du son en cours : une fin (ou un garde-fou) d'un son précédent est ignorée.
    private var generation = 0
    /// Suivi de la position de lecture du son en cours.
    private var progressTimer: Timer?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Démarre le moteur à l'avance : le premier son ne commence pas en retard.
    func prepare() {
        do { try start() } catch { DiagnosticLog.shared.log("audio", "moteur : \(error)") }
    }

    func start() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        if !player.isPlaying { player.play() }
    }

    func stop() {
        generation += 1
        progressTimer?.invalidate()
        progressTimer = nil
        player.stop()
        engine.stop()
    }

    /// Joue un son et appelle `completion` une fois, à la fin réelle du son (sur le fil principal).
    func play(_ kind: Kind, side: Side, completion: (() -> Void)? = nil) {
        do { try start() } catch {
            DiagnosticLog.shared.log("audio", "moteur : \(error)")
            completion?()
            return
        }
        generation += 1
        let current = generation
        let requested = Date()
        var done = false
        let finish: (String) -> Void = { [weak self] how in
            guard let self, !done, current == self.generation else { return }
            done = true
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            DiagnosticLog.shared.log("audio", String(format: "fin de \(kind) (%@) après %.2f s pour %.2f s de son",
                                                     how, Date().timeIntervalSince(requested), kind.duration))
            completion?()
        }
        let buffer = makeBuffer(kind, side: side)
        // Interrompt un son précédent éventuel : un seul son à la fois. Le lecteur repart de zéro.
        progressTimer?.invalidate()
        player.stop()
        player.play()
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { finish("signal de macOS") } }
        }
        // Position de lecture : fin dès que tout le son est passé dans la sortie (plus sa latence).
        // Garde-fou : 0,4 s après la fin prévue une fois la lecture commencée, 1,5 s si elle ne commence jamais.
        let frames = Double(buffer.frameLength)
        let latency = engine.outputNode.presentationLatency
        var startedAt: Date?
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let nodeTime = self.player.lastRenderTime, let playerTime = self.player.playerTime(forNodeTime: nodeTime),
                   playerTime.sampleTime > 0 {
                    if startedAt == nil { startedAt = Date() }
                    if Double(playerTime.sampleTime) / playerTime.sampleRate >= frames / self.sampleRate + latency {
                        finish("position de lecture")
                        return
                    }
                }
                let now = Date()
                if let startedAt, now.timeIntervalSince(startedAt) > kind.duration + latency + 0.4 {
                    finish("garde-fou")
                } else if now.timeIntervalSince(requested) > kind.duration + 1.5 {
                    finish(startedAt == nil ? "garde-fou, lecture jamais commencée" : "garde-fou")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
        DiagnosticLog.shared.log("audio", "lecture \(kind) côté \(side)")
    }

    private func makeBuffer(_ kind: Kind, side: Side) -> AVAudioPCMBuffer {
        let duration = kind.duration
        let frames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        // Volume prudent : amplitude limitée, montées et descentes progressives (pas de claquement).
        let amplitude: Float = 0.45
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let frequency: Double
            var envelope: Double
            switch kind {
            case .sweep:
                frequency = 250 * pow(32, t / duration)   // 250 Hz → 8 kHz, logarithmique
                envelope = min(1, t / 0.08, (duration - t) / 0.08)
            case .pips:
                frequency = 500
                // Trois bips de 0,35 s séparés de 0,3 s, montée et descente de 15 ms.
                let slot = t.truncatingRemainder(dividingBy: 0.65)
                envelope = slot < 0.35 ? min(1, slot / 0.015, (0.35 - slot) / 0.015) : 0
            }
            phase += 2 * .pi * frequency / sampleRate
            let wave: Double
            switch kind {
            case .sweep: wave = sin(phase)
            case .pips:
                // Harmoniques 1 à 12 de 500 Hz en 1/n, ramenées à l'amplitude d'un son pur.
                wave = (1...12).reduce(0.0) { $0 + sin(Double($1) * phase) / Double($1) } / 1.6
            }
            let sample = Float(wave * max(0, envelope)) * amplitude
            left[i] = side == .right ? 0 : sample
            right[i] = side == .left ? 0 : sample
        }
        return buffer
    }
}
