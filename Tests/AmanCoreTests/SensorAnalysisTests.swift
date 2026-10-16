import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

@Suite("Capteurs · SMC et ventilateurs")
struct SensorAnalysisTests {
    private func find(_ list: [Measurement], _ id: String) -> Measurement? { list.first { $0.id == id } }

    @Test("Octets réels du MacBookPro16,1 : ventilateurs en flt, sondes en sp78")
    func decodesRealBytes() {
        // Lus sur la machine de développement (2026-10-16).
        #expect(SMCValue.decode(type: "ui8 ", bytes: [0x02]) == 2)                                   // FNum
        #expect(SMCValue.decode(type: "flt ", bytes: [0x88, 0xd6, 0x50, 0x45]).map { Int($0) } == 3341) // F0Ac
        #expect(SMCValue.decode(type: "flt ", bytes: [0x00, 0x80, 0xaf, 0x45]) == 5616)              // F0Mx
        #expect(SMCValue.decode(type: "sp78", bytes: [0x3e, 0x0c]) == 62.046875)                     // TCXC
        #expect(SMCValue.decode(type: "ui32", bytes: [0x00, 0x00, 0x04, 0x8c]) == 1164)              // #KEY
    }

    @Test("fpe2 (anciens Mac Intel), sp78 négatif, types inconnus et octets manquants")
    func decodesOtherTypes() {
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x1c, 0x20]) == 1800)
        #expect(SMCValue.decode(type: "sp78", bytes: [0xff, 0x00]) == -1)
        #expect(SMCValue.decode(type: "ch8*", bytes: [0x41]) == nil)
        #expect(SMCValue.decode(type: "flt ", bytes: [0x00, 0x00]) == nil)
        #expect(SMCValue.decode(type: "sp78", bytes: []) == nil)
        #expect(SMCValue.decode(type: "flt ", bytes: [0x00, 0x00, 0xc0, 0x7f]) == nil)  // NaN
    }

    @Test("Moyenne des sondes Apple Silicon : valeurs aberrantes écartées")
    func averagesPlausibleTemperatures() {
        #expect(SensorAnalysis.averageTemperature([40, 50, 0, 250]) == 45)
        #expect(SensorAnalysis.averageTemperature([0, -3, 400]) == nil)
        #expect(SensorAnalysis.averageTemperature([]) == nil)
    }

    @Test("Mac avec ventilateurs : nombre, vitesses, température, rien de vert sans jugement")
    func normalReading() {
        let r = SensorReading(smcAvailable: true, fanCount: 2, fanSpeeds: [3341, 3085], cpuTemperature: 62.05, method: "AppleSMC · FNum")
        let m = SensorAnalysis.measurements(r, expectsFan: true)
        #expect(find(m, MetricID.fanCount)?.value == .int(2))
        #expect(find(m, MetricID.fanCount)?.status == .info)
        #expect(find(m, MetricID.fanSpeed)?.value == .int(3341))
        #expect(find(m, MetricID.fanSpeed)?.status == .info)
        #expect(find(m, MetricID.cpuTemperature)?.value == .double(62.1))
        #expect(find(m, MetricID.cpuTemperature)?.status == .info)
        #expect(!m.contains { $0.status == .good })
    }

    @Test("Mac sans ventilateur : « Pas de ventilateur sur ce modèle », pas « Non disponible »")
    func fanless() {
        // Même si le SMC est illisible : le catalogue suffit à le dire.
        for reading in [SensorReading(smcAvailable: true, fanCount: 0, cpuTemperature: 40), SensorReading(smcAvailable: false)] {
            let m = SensorAnalysis.measurements(reading, expectsFan: false)
            let fans = find(m, MetricID.fanCount)
            #expect(fans?.status == .info)
            #expect(fans?.value == .int(0))
            #expect(fans?.displayText == L("No fan on this model", "Pas de ventilateur sur ce modèle"))
            #expect(find(m, MetricID.fanSpeed) == nil)
        }
    }

    @Test("Ventilateur attendu mais aucun signalé : à surveiller, jamais vert")
    func missingFan() {
        let m = SensorAnalysis.measurements(SensorReading(smcAvailable: true, fanCount: 0, cpuTemperature: 50), expectsFan: true)
        #expect(find(m, MetricID.fanCount)?.status == .watch)
        // Modèle inconnu : simple information.
        let unknown = SensorAnalysis.measurements(SensorReading(smcAvailable: true, fanCount: 0), expectsFan: nil)
        #expect(find(unknown, MetricID.fanCount)?.status == .info)
    }

    @Test("SMC illisible : non disponible partout")
    func unreadable() {
        let m = SensorAnalysis.measurements(SensorReading(smcAvailable: false), expectsFan: true)
        #expect(find(m, MetricID.fanCount)?.status == .unavailable)
        #expect(find(m, MetricID.cpuTemperature)?.status == .unavailable)
        #expect(find(m, MetricID.fanSpeed) == nil)
    }

    @Test("Vitesses illisibles ou aberrantes : non disponible, jamais 0")
    func unreadableSpeeds() {
        let m = SensorAnalysis.measurements(SensorReading(smcAvailable: true, fanCount: 2, fanSpeeds: [nil, 99_999]), expectsFan: true)
        #expect(find(m, MetricID.fanSpeed)?.status == .unavailable)
        #expect(find(m, MetricID.fanSpeed)?.value == nil)
    }

    @Test("Température élevée au repos : à surveiller, jamais problème")
    func hotAtRest() {
        let m = SensorAnalysis.measurements(SensorReading(smcAvailable: true, fanCount: 1, fanSpeeds: [5000], cpuTemperature: 101), expectsFan: true)
        #expect(find(m, MetricID.cpuTemperature)?.status == .watch)
        #expect(!m.contains { $0.status == .problem })
    }

    @Test("Catalogue : ventilateur selon le modèle, capteurs selon le type de Mac")
    func profileFlags() {
        #expect(DeviceProfile.make(modelIdentifier: "MacBookAir10,1", simulated: true).hasFan == false)   // M1
        #expect(DeviceProfile.make(modelIdentifier: "MacBookAir9,1", simulated: true).hasFan == true)     // Intel 2020
        #expect(DeviceProfile.make(modelIdentifier: "MacBook10,1", simulated: true).hasFan == false)      // 12 pouces 2017
        #expect(DeviceProfile.make(modelIdentifier: "MacBookPro16,1", simulated: true).hasFan == true)
        #expect(DeviceProfile.make(modelIdentifier: "Mac99,9", simulated: true).hasFan == nil)
        let mini = DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
        #expect(!mini.hasLid && !mini.hasAmbientLightSensor && !mini.hasKeyboardBacklight)
        let imac = DeviceProfile.make(modelIdentifier: "iMac21,1", simulated: true)
        #expect(!imac.hasLid && imac.hasAmbientLightSensor && !imac.hasKeyboardBacklight)
        #expect(TestID.applicable(to: mini).allSatisfy { ![.lid, .ambientLight, .keyboardBacklight].contains($0) })
        let laptop = DeviceProfile.make(modelIdentifier: "MacBookPro18,3", simulated: true)
        #expect([TestID.lid, .ambientLight, .keyboardBacklight].allSatisfy(TestID.applicable(to: laptop).contains))
    }
}

@Suite("Capteurs · tests guidés")
struct SensorGuidedTests {
    @Test("Capot : fermeture et ouverture vues par le capteur, ou veille et réveil → mesuré, bon")
    func lidDetected() {
        let bySensor = SensorTests.lidResult(LidObservation(stateReadable: true, sawClosed: true, sawOpened: true), screenReacted: nil)
        #expect(bySensor?.status == .good)
        #expect(bySensor?.provenance == .measuredAuto)
        let bySleep = SensorTests.lidResult(LidObservation(stateReadable: false, slept: true, woke: true), screenReacted: nil)
        #expect(bySleep?.status == .good)
        #expect(bySleep?.provenance == .measuredAuto)
        // Fermé sans réouverture vue : pas encore de conclusion.
        #expect(SensorTests.lidResult(LidObservation(stateReadable: true, sawClosed: true), screenReacted: nil) == nil)
    }

    @Test("Capot : réponse de la personne quand rien n'est détecté")
    func lidAnswered() {
        let unreadable = LidObservation(stateReadable: false)
        let yes = SensorTests.lidResult(unreadable, screenReacted: true)
        #expect(yes?.status == .good)
        #expect(yes?.provenance == .userObserved)
        let no = SensorTests.lidResult(unreadable, screenReacted: false)
        #expect(no?.status == .problem)
        #expect(no?.outcome == .failed)
        // État du capot lisible mais immobile, alors que la personne a vu l'écran réagir : à surveiller.
        #expect(SensorTests.lidResult(LidObservation(stateReadable: true), screenReacted: true)?.status == .watch)
    }

    @Test("Capot : écran externe → test bloqué seulement si l'état du capot est illisible")
    func lidExternalDisplay() {
        #expect(SensorTests.lidNeedsExternalDisplayUnplugged(stateReadable: false, externalDisplay: true))
        #expect(!SensorTests.lidNeedsExternalDisplayUnplugged(stateReadable: true, externalDisplay: true))
        #expect(!SensorTests.lidNeedsExternalDisplayUnplugged(stateReadable: false, externalDisplay: false))
    }

    @Test("Luminosité : baisse mesurée → bon ; sinon la réponse décide, désactivée → non testé")
    func ambient() {
        let measured = SensorTests.ambientResult(brightnessBefore: 0.81, brightnessLowest: 0.45, answer: nil)
        #expect(measured?.status == .good)
        #expect(measured?.provenance == .measuredAuto)
        // Baisse trop faible ou luminosité illisible (Apple Silicon) : la question est posée.
        #expect(SensorTests.ambientResult(brightnessBefore: 0.81, brightnessLowest: 0.79, answer: nil) == nil)
        #expect(SensorTests.ambientResult(brightnessBefore: nil, brightnessLowest: nil, answer: nil) == nil)
        #expect(SensorTests.ambientResult(brightnessBefore: nil, brightnessLowest: nil, answer: .changed)?.provenance == .userObserved)
        let none = SensorTests.ambientResult(brightnessBefore: nil, brightnessLowest: nil, answer: .noChange)
        #expect(none?.status == .watch)
        let off = SensorTests.ambientResult(brightnessBefore: nil, brightnessLowest: nil, answer: .automaticBrightnessOff)
        #expect(off?.status == .notTested)
        #expect(off?.outcome == .skipped)
    }

    @Test("Rétroéclairage : constaté par la personne")
    func backlight() {
        #expect(SensorTests.keyboardBacklightResult(works: true).status == .good)
        #expect(SensorTests.keyboardBacklightResult(works: false).status == .problem)
        #expect(SensorTests.keyboardBacklightResult(works: false).provenance == .userObserved)
    }
}
