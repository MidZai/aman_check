import Foundation
import DiskHealthCore

// Capteurs (spec §6.6) : ventilateurs et température lus dans le SMC, et décisions des tests guidés
// du capot, de la luminosité ambiante et du rétroéclairage du clavier. Aucune lecture ici : l'app lit,
// ce fichier décide (testable avec des valeurs fixes).

/// Valeur brute d'une clé SMC, décodée selon le type annoncé par le SMC lui-même.
/// Le type ne dépend pas seulement de la puce : sur le MacBookPro16,1 (Intel T2), les vitesses des
/// ventilateurs sont en `flt` et les températures en `sp78`.
public enum SMCValue {
    /// `nil` si le type est inconnu ou si le nombre d'octets ne correspond pas.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        func be16() -> UInt16? { bytes.count >= 2 ? UInt16(bytes[0]) << 8 | UInt16(bytes[1]) : nil }
        switch type {
        case "ui8 ", "ui8":
            return bytes.first.map(Double.init)
        case "ui16":
            return be16().map(Double.init)
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "sp78":
            // Virgule fixe signée 8.8, gros-boutiste.
            return be16().map { Double(Int16(bitPattern: $0)) / 256 }
        case "fpe2":
            // Virgule fixe non signée 14.2, gros-boutiste.
            return be16().map { Double($0) / 4 }
        case "flt ", "flt":
            // Flottant 32 bits, petit-boutiste.
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        default:
            return nil
        }
    }

    /// Sondes du processeur des Mac Intel, de la plus représentative à la moins représentative :
    /// boîtier (PECI), puis puce, puis proximité.
    public static let intelCPUTemperatureKeys = ["TCXC", "TC0E", "TC0F", "TC0D", "TC0P"]
    /// Apple Silicon : sondes des cœurs, préfixe « Tp » (M1, M2). TODO: à valider sur machine réelle (M3, M4).
    public static let appleSiliconCPUTemperaturePrefix = "Tp"

    /// Température plausible d'une sonde de processeur, en °C.
    public static func isPlausibleTemperature(_ celsius: Double) -> Bool { (5...130).contains(celsius) }
    /// Vitesse plausible d'un ventilateur, en tours par minute.
    public static func isPlausibleFanSpeed(_ rpm: Double) -> Bool { (0...12_000).contains(rpm) }
}

/// Ce que l'app a pu lire dans le SMC. `smcAvailable` faux : le service AppleSMC n'a pas répondu
/// (machine virtuelle, restriction du système).
public struct SensorReading: Sendable, Equatable {
    public var smcAvailable: Bool
    public var fanCount: Int?
    /// Une entrée par ventilateur (`F0Ac`, `F1Ac`…) ; `nil` : vitesse illisible.
    public var fanSpeeds: [Double?]
    public var cpuTemperature: Double?
    /// Clés lues, pour la section Avancé (« FNum, F0Ac, F1Ac, TCXC »).
    public var method: String?

    public init(smcAvailable: Bool, fanCount: Int? = nil, fanSpeeds: [Double?] = [], cpuTemperature: Double? = nil, method: String? = nil) {
        self.smcAvailable = smcAvailable
        self.fanCount = fanCount
        self.fanSpeeds = fanSpeeds
        self.cpuTemperature = cpuTemperature
        self.method = method
    }
}

public enum SensorAnalysis {
    /// Seuil indicatif d'un processeur au repos. Au-delà : « à surveiller », jamais « problème » sur une
    /// seule température (spec §6.6).
    public static let restingTemperatureWatch = 95.0

    /// Moyenne des sondes plausibles (Apple Silicon : plusieurs sondes de cœurs).
    public static func averageTemperature(_ values: [Double]) -> Double? {
        let valid = values.filter(SMCValue.isPlausibleTemperature)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    /// `expectsFan` : le catalogue dit si ce modèle a un ventilateur (`DeviceProfile.hasFan`) ; `nil` : modèle inconnu.
    public static func measurements(_ r: SensorReading, expectsFan: Bool?, now: Date = Date()) -> [Measurement] {
        var result: [Measurement] = []
        let method = r.method ?? "AppleSMC"
        let noFan = L("No fan on this model", "Pas de ventilateur sur ce modèle")
        let unreadable = L("The system management controller (SMC) of this Mac could not be read.",
                           "Le contrôleur de gestion du système (SMC) de ce Mac n'a pas pu être lu.")

        // Nombre de ventilateurs.
        if expectsFan == false {
            // Mac sans ventilateur (MacBook Air M1 et suivants, MacBook 12 pouces) : une information, pas une absence.
            result.append(Measurement(id: MetricID.fanCount, value: .int(0), status: .info, method: method, collectedAt: now,
                                      display: noFan,
                                      detail: L("Cooled without a fan: silent, it slows down a little under long heavy work.",
                                                "Refroidi sans ventilateur : silencieux, il ralentit un peu sous une longue charge lourde.")))
        } else if !r.smcAvailable || r.fanCount == nil {
            result.append(.unavailable(MetricID.fanCount, note: unreadable, method: method))
        } else if let count = r.fanCount, count == 0 {
            if expectsFan == true {
                result.append(Measurement(id: MetricID.fanCount, value: .int(0), status: .watch, method: method, collectedAt: now,
                                          display: L("No fan reported", "Aucun ventilateur signalé"),
                                          note: L("This model has a fan, but the Mac reports none. It may be disconnected or faulty: have it checked.",
                                                  "Ce modèle a un ventilateur, mais le Mac n'en signale aucun. Il peut être débranché ou défectueux : faites-le vérifier.")))
            } else {
                result.append(Measurement(id: MetricID.fanCount, value: .int(0), status: .info, method: method, collectedAt: now,
                                          display: L("No fan reported", "Aucun ventilateur signalé")))
            }
        } else if let count = r.fanCount {
            result.append(Measurement(id: MetricID.fanCount, value: .int(Int64(count)), status: .info, method: method, collectedAt: now,
                                      display: count == 1 ? L("1 fan", "1 ventilateur") : L("\(count) fans", "\(count) ventilateurs")))
        }

        // Vitesse actuelle (seulement s'il y a des ventilateurs).
        if expectsFan != false, let count = r.fanCount, count > 0 {
            let speeds = r.fanSpeeds.prefix(count).map { $0.flatMap { SMCValue.isPlausibleFanSpeed($0) ? $0 : nil } }
            let readable = speeds.compactMap { $0 }
            if readable.isEmpty {
                result.append(.unavailable(MetricID.fanSpeed, note: L("The fan speed could not be read.", "La vitesse des ventilateurs n'a pas pu être lue."),
                                           method: method))
            } else {
                // Virgule plutôt que « · », qui se lit comme le zéro arabe (٠) entre deux nombres.
                let text = speeds.map { $0.map { fanSpeedText($0) } ?? "—" }.joined(separator: ", ")
                result.append(Measurement(id: MetricID.fanSpeed, value: .int(Int64(readable.max()!.rounded())), unit: "rpm", status: .info,
                                          method: method, collectedAt: now, display: text,
                                          note: L("At rest, fans can be slow or even stopped.",
                                                  "Au repos, les ventilateurs peuvent tourner lentement, voire être arrêtés.")))
            }
        }

        // Température du processeur.
        if let t = r.cpuTemperature, SMCValue.isPlausibleTemperature(t) {
            let high = t >= restingTemperatureWatch
            result.append(Measurement(id: MetricID.cpuTemperature, value: .double((t * 10).rounded() / 10), unit: "°C",
                                      status: high ? .watch : .info, method: method, collectedAt: now,
                                      display: Formatters.temperature(Int(t.rounded())),
                                      note: high
                                        ? L("High for a Mac at rest (indicative threshold: \(Int(restingTemperatureWatch)) °C). Check that nothing heavy is running, then that the vents are not blocked.",
                                            "Élevée pour un Mac au repos (seuil indicatif : \(Int(restingTemperatureWatch)) °C). Vérifiez que rien de lourd ne tourne, puis que les aérations ne sont pas bouchées.")
                                        : nil))
        } else {
            result.append(.unavailable(MetricID.cpuTemperature,
                                       note: r.smcAvailable ? L("No processor temperature sensor could be read on this Mac.",
                                                                "Aucune sonde de température du processeur n'a pu être lue sur ce Mac.")
                                                            : unreadable,
                                       method: method))
        }
        return result
    }

    /// Capteur de luminosité lu pendant l'analyse : il répond (information). Sa réaction se juge dans le
    /// test guidé. `expected` : le modèle en a un ; `nil` si le Mac n'en a pas (aucune ligne).
    public static func ambientLightMeasurement(lux: Double?, expected: Bool, now: Date = Date()) -> Measurement? {
        guard expected else { return nil }
        let method = "IOHIDManager · Sensor page 0x20, Ambient Light 0x41, Illuminance 0x4D1"
        guard let lux, lux.isFinite, lux >= 0 else {
            return .unavailable(MetricID.ambientLight,
                                note: L("This Mac does not let the app read the light sensor: the guided test asks you to look at the screen instead.",
                                        "Ce Mac ne laisse pas l'app lire le capteur de luminosité : le test guidé vous demande plutôt de regarder l'écran."),
                                method: method)
        }
        return Measurement(id: MetricID.ambientLight, value: .double((lux * 10).rounded() / 10), unit: "lux", status: .info, method: method,
                           collectedAt: now, display: SensorTests.lux(lux),
                           detail: L("Light measured next to the camera. Its reaction is checked by the guided test.",
                                     "Lumière mesurée près de la caméra. Sa réaction se vérifie dans le test guidé."))
    }

    /// « 1 812 tr/min ».
    public static func fanSpeedText(_ rpm: Double) -> String {
        "\(Formatters.integer(Int(rpm.rounded())))\(Formatters.unitSpace)\(L("rpm", "tr/min"))"
    }
}

// MARK: - Tests guidés des capteurs

/// Ce que l'app a vu pendant le test du capot.
public struct LidObservation: Sendable, Equatable {
    /// `AppleClamshellState` lisible dans le registre IOKit.
    public var stateReadable: Bool
    public var sawClosed: Bool
    public var sawOpened: Bool
    /// Notifications de mise en veille et de réveil reçues pendant le test.
    public var slept: Bool
    public var woke: Bool

    public init(stateReadable: Bool, sawClosed: Bool = false, sawOpened: Bool = false, slept: Bool = false, woke: Bool = false) {
        self.stateReadable = stateReadable
        self.sawClosed = sawClosed
        self.sawOpened = sawOpened
        self.slept = slept
        self.woke = woke
    }

    /// Fermeture et réouverture vues par l'app, sans rien demander à la personne.
    public var detected: Bool { (sawClosed && sawOpened) || (slept && woke) }
}

public enum SensorTests {
    /// Le test du capot ne peut pas démarrer : un écran externe garde le Mac éveillé capot fermé, et sans lecture
    /// de l'état du capot, l'app ne verrait rien. La personne débranche l'écran ou passe le test.
    public static func lidNeedsExternalDisplayUnplugged(stateReadable: Bool, externalDisplay: Bool) -> Bool {
        externalDisplay && !stateReadable
    }

    /// `screenReacted` : réponse à « L'écran s'est-il éteint à la fermeture et rallumé à l'ouverture ? »
    /// (`nil` tant que la question n'a pas été posée).
    public static func lidResult(_ o: LidObservation, screenReacted: Bool?) -> TestResult? {
        if o.detected {
            let how = o.sawClosed && o.sawOpened
                ? L("Lid closing and opening detected by the lid sensor", "Fermeture et ouverture du capot détectées par le capteur")
                : L("Sleep on closing and wake on opening detected", "Mise en veille à la fermeture et réveil à l'ouverture détectés")
            return TestResult(test: .lid, outcome: .passed, provenance: .measuredAuto, summary: how)
        }
        guard let screenReacted else { return nil }
        if screenReacted {
            // La personne a vu l'écran réagir, mais l'app, qui lisait l'état du capot, n'a rien vu : à surveiller.
            if o.stateReadable {
                return TestResult(test: .lid, outcome: .passed, status: .watch, provenance: .userObserved,
                                  summary: L("Screen reacted to the lid, but the sensor state did not change",
                                             "L'écran a réagi au capot, mais l'état du capteur n'a pas changé"),
                                  details: [L("Run the test again; if it repeats, have the lid sensor checked.",
                                              "Refaites le test ; si cela se répète, faites vérifier le capteur du capot.")])
            }
            return TestResult(test: .lid, outcome: .passed, provenance: .userObserved,
                              summary: L("Screen turned off on closing and back on on opening", "L'écran s'est éteint à la fermeture et rallumé à l'ouverture"))
        }
        return TestResult(test: .lid, outcome: .failed, provenance: o.stateReadable ? .measuredAuto : .userObserved,
                          summary: L("The Mac did not react to the lid", "Le Mac n'a pas réagi au capot"),
                          details: [L("A faulty lid sensor keeps the Mac awake with the lid closed, or asleep once opened.",
                                      "Un capteur de capot défectueux laisse le Mac éveillé capot fermé, ou endormi une fois ouvert.")])
    }

    /// Réponse au test de luminosité ambiante, quand l'app ne peut rien mesurer elle-même.
    public enum AmbientAnswer: Sendable {
        case changed, noChange, automaticBrightnessOff
    }

    // Capteur lu directement (HID, page Capteurs 0x20, usage 0x41, champ Éclairement 0x4D1), en lux.
    // Le geste peut être de couvrir le capteur ou de l'éclairer à la torche : on cherche un écart net
    // dans un sens ou dans l'autre. Constaté sur le MacBookPro16,1 : pièce à 5,8 lux, la main ne fait
    // presque rien baisser, la torche fait monter.

    /// Écart minimal entre la plus forte et la plus faible valeur, en lux.
    public static let ambientMinimumLuxChange = 3.0
    /// Rapport minimal entre elles (la plus faible est comptée au moins 1 lux, pour les pièces très sombres).
    public static let ambientMinimumLuxRatio = 3.0

    /// Écart net vu par le capteur depuis le début : `(départ, valeur la plus éloignée)`, sinon `nil`.
    public static func ambientLuxReaction(baseline: Double, samples: [Double]) -> (from: Double, to: Double)? {
        let values = [baseline] + samples.filter { $0.isFinite && $0 >= 0 }
        guard let high = values.max(), let low = values.min() else { return nil }
        guard high - low >= ambientMinimumLuxChange, high / max(low, 1) >= ambientMinimumLuxRatio else { return nil }
        // La valeur la plus éloignée du départ (couvert : la plus basse ; éclairé : la plus haute).
        let to = abs(high - baseline) >= abs(baseline - low) ? high : low
        return (baseline, to)
    }

    /// Le capteur a réagi : bon, mesuré automatiquement.
    public static func ambientSensorResult(from: Double, to: Double) -> TestResult {
        TestResult(test: .ambientLight, outcome: .passed, provenance: .measuredAuto,
                   summary: L("The light sensor went from \(lux(from)) to \(lux(to))", "Le capteur de luminosité est passé de \(lux(from)) à \(lux(to))"))
    }

    /// Le capteur se lit mais n'a pas réagi alors que la personne dit l'avoir éclairé ou couvert : à surveiller.
    public static func ambientSensorNoReaction(baseline: Double) -> TestResult {
        TestResult(test: .ambientLight, outcome: .failed, status: .watch, provenance: .measuredAuto,
                   summary: L("The light sensor stayed at about \(lux(baseline))", "Le capteur de luminosité est resté vers \(lux(baseline))"),
                   details: [L("It did not react to the light or to the hand. It may be covered (sticker, screen protector) or faulty.",
                               "Il n'a réagi ni à la lumière ni à la main. Il peut être masqué (autocollant, film de protection) ou défectueux.")])
    }

    /// Changement de luminosité de l'écran (0–1) à partir duquel l'app considère que le capteur a réagi.
    public static let ambientMinimumBrightnessChange = 0.05

    /// Repli quand le capteur ne se lit pas : luminosité de l'écran intégré au début et valeurs relevées
    /// pendant le test, dans les deux sens (`nil` : illisible, cas des Mac Apple Silicon par l'interface
    /// publique). Sinon la réponse de la personne.
    public static func ambientResult(brightnessBefore: Double?, brightnessSamples: [Double], answer: AmbientAnswer?) -> TestResult? {
        if let before = brightnessBefore,
           let farthest = brightnessSamples.max(by: { abs($0 - before) < abs($1 - before) }),
           abs(farthest - before) >= ambientMinimumBrightnessChange {
            return TestResult(test: .ambientLight, outcome: .passed, provenance: .measuredAuto,
                              summary: L("Screen brightness went from \(percent(before)) to \(percent(farthest)) by itself",
                                         "La luminosité de l'écran est passée d'elle-même de \(percent(before)) à \(percent(farthest))"))
        }
        switch answer {
        case nil:
            return nil
        case .changed?:
            return TestResult(test: .ambientLight, outcome: .passed, provenance: .userObserved,
                              summary: L("Screen brightness changed by itself", "La luminosité de l'écran a changé d'elle-même"))
        case .noChange?:
            return TestResult(test: .ambientLight, outcome: .failed, status: .watch, provenance: .userObserved,
                              summary: L("Screen brightness did not change", "La luminosité de l'écran n'a pas changé"),
                              details: [L("The sensor may be faulty, or covered by a sticker or a screen protector.",
                                          "Le capteur peut être défectueux, ou masqué par un autocollant ou un film de protection.")])
        case .automaticBrightnessOff?:
            return .notTested(.ambientLight, reason: L("Automatic brightness is off: check by hand", "Luminosité automatique désactivée : à vérifier à la main"))
        }
    }

    /// « 5,8 lux », « 480 lux ».
    public static func lux(_ value: Double) -> String {
        let text = value < 10 ? Formatters.decimal((value * 10).rounded() / 10) : Formatters.integer(Int(value.rounded()))
        return "\(text)\(Formatters.unitSpace)lux"
    }

    public static func keyboardBacklightResult(works: Bool) -> TestResult {
        works
            ? TestResult(test: .keyboardBacklight, outcome: .passed, provenance: .userObserved,
                         summary: L("Keyboard backlight works", "Le rétroéclairage du clavier fonctionne"))
            : TestResult(test: .keyboardBacklight, outcome: .failed, provenance: .userObserved,
                         summary: L("Keyboard backlight does not light up", "Le rétroéclairage du clavier ne s'allume pas"))
    }

    private static func percent(_ value: Double) -> String {
        Formatters.percentage(value * 100)
    }
}
