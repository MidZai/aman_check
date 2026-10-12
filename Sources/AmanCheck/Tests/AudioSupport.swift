import Foundation
import AVFoundation
import CoreAudio
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
@MainActor
final class ToneGenerator {
    enum Side { case left, right, both }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double = 48_000

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        if !engine.isRunning { try engine.start() }
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// Joue un son et appelle `completion` à la fin (sur le fil principal).
    func play(_ kind: Kind, side: Side, completion: (() -> Void)? = nil) {
        do { try start() } catch {
            DiagnosticLog.shared.log("audio", "moteur : \(error)")
            completion?()
            return
        }
        let buffer = makeBuffer(kind, side: side)
        player.scheduleBuffer(buffer, at: nil, options: []) {
            DispatchQueue.main.async { completion?() }
        }
        DiagnosticLog.shared.log("audio", "lecture \(kind) côté \(side)")
    }

    enum Kind { case lowTone, sweep, beep }

    private func makeBuffer(_ kind: Kind, side: Side) -> AVAudioPCMBuffer {
        let duration: Double
        switch kind {
        case .lowTone: duration = 2.5
        case .sweep: duration = 4
        case .beep: duration = 0.8
        }
        let frames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        // Volume prudent : amplitude limitée, montée et descente progressives (pas de claquement).
        let amplitude: Float = 0.35
        let fade = 0.08 * sampleRate
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let frequency: Double
            switch kind {
            case .lowTone: frequency = 110
            case .sweep: frequency = 100 * pow(100, t / duration)   // 100 Hz → 10 kHz, logarithmique
            case .beep: frequency = 880
            }
            phase += 2 * .pi * frequency / sampleRate
            var envelope = 1.0
            if Double(i) < fade { envelope = Double(i) / fade }
            if Double(Int(frames) - i) < fade { envelope = Double(Int(frames) - i) / fade }
            let sample = Float(sin(phase) * envelope) * amplitude
            left[i] = side == .right ? 0 : sample
            right[i] = side == .left ? 0 : sample
        }
        return buffer
    }
}
