import Foundation
import DiskHealthCore

// Test de performance (spec §7.8) : détecter un Mac qui ne tient pas ses performances sous charge
// (ventilateur hors service, pâte thermique sèche, puce abîmée). Pas de score affiché comme une note.
// Ce fichier décide ; l'app mesure (PerformanceRunner).

/// Source d'alimentation pendant le test.
public enum PowerSource: String, Codable, Sendable {
    case adapter, battery, unknown

    public var label: String {
        switch self {
        case .adapter: return L("on power adapter", "sur secteur")
        case .battery: return L("on battery", "sur batterie")
        case .unknown: return L("power source unknown", "alimentation inconnue")
        }
    }
}

/// Mesures brutes d'un passage complet.
public struct PerformanceRun: Codable, Sendable, Equatable {
    /// Débit du processeur, en GFLOPS (double précision), une valeur par tranche de 2 s.
    public var cpuSlices: [Double]
    /// Débit du GPU, en GFLOPS (simple précision), par tranche de 2 s ; `nil` : Metal indisponible.
    public var gpuSlices: [Double]?
    /// Copie mémoire séquentielle, en Go/s ; `nil` : non mesurée.
    public var memoryGBps: Double?
    /// Températures du processeur relevées toutes les 2 s (`nil` : illisible).
    public var temperatures: [Double?]
    /// Vitesse maximale des ventilateurs à chaque relevé (`nil` : illisible).
    public var fanSpeeds: [Double?]
    public var duration: TimeInterval
    public var powerAtStart: PowerSource
    public var powerAtEnd: PowerSource
    /// `machdep.cpu.brand_string` : clé de la table de référence.
    public var chip: String?

    public init(cpuSlices: [Double], gpuSlices: [Double]?, memoryGBps: Double?, temperatures: [Double?] = [], fanSpeeds: [Double?] = [],
                duration: TimeInterval, powerAtStart: PowerSource = .unknown, powerAtEnd: PowerSource = .unknown, chip: String? = nil) {
        self.cpuSlices = cpuSlices
        self.gpuSlices = gpuSlices
        self.memoryGBps = memoryGBps
        self.temperatures = temperatures
        self.fanSpeeds = fanSpeeds
        self.duration = duration
        self.powerAtStart = powerAtStart
        self.powerAtEnd = powerAtEnd
        self.chip = chip
    }
}

/// Valeurs de référence d'une puce, mesurées sur une vraie machine (jamais inventées).
public struct PerformanceReferenceEntry: Codable, Sendable, Equatable {
    public let cpuGflops: Double?
    public let gpuGflops: Double?
    /// Machine et date de la mesure (« MacBookPro16,1, 2026-10-16 »).
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case cpuGflops = "cpu_gflops"
        case gpuGflops = "gpu_gflops"
        case source
    }

    public init(cpuGflops: Double?, gpuGflops: Double?, source: String? = nil) {
        self.cpuGflops = cpuGflops
        self.gpuGflops = gpuGflops
        self.source = source
    }
}

/// Table `{ "chip identifier": { "cpu_gflops": x, "gpu_gflops": y, "source": "…" } }` (PerformanceReference.json).
public struct PerformanceReference: Sendable, Equatable {
    public let entries: [String: PerformanceReferenceEntry]

    public init(entries: [String: PerformanceReferenceEntry]) {
        self.entries = entries
    }

    /// Table illisible ou absente : vide (aucune référence), jamais d'erreur.
    public init(json data: Data?) {
        guard let data, let decoded = try? JSONDecoder().decode([String: PerformanceReferenceEntry].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    /// Recherche par identifiant de puce, sans tenir compte des espaces superflus ni de la casse.
    public func entry(for chip: String?) -> PerformanceReferenceEntry? {
        guard let chip else { return nil }
        let key = Self.normalize(chip)
        return entries.first { Self.normalize($0.key) == key }?.value
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum PerformanceAnalysis {
    /// Durées prévues, en secondes (≤ 60 au total, spec §7.8).
    public static let cpuSeconds = 30.0
    public static let gpuSeconds = 20.0
    public static let memorySeconds = 5.0
    public static let sliceSeconds = 2.0

    /// Seuils de stabilité : baisse entre le début et la fin.
    public static let watchDrop = 0.10
    public static let problemDrop = 0.25
    /// En dessous de cette part de la référence : à surveiller (jamais problème : la référence peut être bruitée).
    public static let referenceWatchRatio = 0.80
    /// Ventilateurs restés à l'arrêt : un problème seulement si le processeur a vraiment chauffé.
    public static let hotTemperature = 90.0

    /// Baisse relative entre la moyenne des 3 premières tranches et celle des 3 dernières
    /// (0,18 = −18 %). `nil` avec moins de 6 tranches. Une hausse compte comme 0.
    public static func drop(_ slices: [Double]) -> Double? {
        guard slices.count >= 6 else { return nil }
        let first = slices.prefix(3).reduce(0, +) / 3
        let last = slices.suffix(3).reduce(0, +) / 3
        guard first > 0 else { return nil }
        return max(0, (first - last) / first)
    }

    public static func status(forDrop drop: Double) -> CheckStatus {
        if drop > problemDrop { return .problem }
        if drop >= watchDrop { return .watch }
        return .good
    }

    /// Moyenne des tranches, la première écartée quand il y en a assez (montée en charge).
    public static func average(_ slices: [Double]) -> Double? {
        let used = slices.count > 3 ? Array(slices.dropFirst()) : slices
        guard !used.isEmpty else { return nil }
        return used.reduce(0, +) / Double(used.count)
    }

    /// Aucun test lancé : une seule ligne « Non testé » (comptée comme telle).
    public static func notRun(now: Date = Date(), cancelled: Bool = false) -> [Measurement] {
        [Measurement(id: MetricID.performanceStability, value: nil, status: .notTested, provenance: .derived, collectedAt: now,
                     note: cancelled ? L("Test cancelled before the end.", "Test annulé avant la fin.")
                                     : L("The performance test has not been run. It lasts about a minute.",
                                         "Le test de performance n'a pas été lancé. Il dure environ une minute."))]
    }

    public static func measurements(_ run: PerformanceRun, reference: PerformanceReference, expectsFan: Bool?, now: Date = Date()) -> [Measurement] {
        var result: [Measurement] = []
        let entry = reference.entry(for: run.chip)
        let noReference = L("No reference for this model yet.", "Pas encore de référence pour ce modèle.")

        // Stabilité : la plus forte baisse, processeur ou GPU.
        let drops = [drop(run.cpuSlices), run.gpuSlices.flatMap(drop)].compactMap { $0 }
        if let worst = drops.max() {
            let status = status(forDrop: worst)
            let percent = Int((worst * 100).rounded())
            result.append(Measurement(id: MetricID.performanceStability, value: .int(Int64(percent)), unit: "%", status: status,
                                      provenance: .derived, method: L("Average of the first 3 slices of 2 s compared with the last 3", "Moyenne des 3 premières tranches de 2 s comparée aux 3 dernières"),
                                      collectedAt: now,
                                      display: percent == 0 ? L("Steady under load", "Stable sous charge")
                                                            : L("−\(percent)% under load", "−\(percent) % sous charge"),
                                      // Mesuré sur la machine de développement : un deuxième test enchaîné, Mac déjà chaud, a
                                      // donné −66 % alors que le premier était stable.
                                      detail: status == .good ? nil
                                        : L("If the Mac was already warm, let it cool for a few minutes and run the test again to confirm.",
                                            "Si le Mac était déjà chaud, laissez-le refroidir quelques minutes et refaites le test pour confirmer."),
                                      note: status == .problem
                                        ? L("Performance drops sharply under load. Check the cooling.", "Les performances baissent fortement sous charge. Vérifiez la ventilation.")
                                        : status == .watch
                                            ? L("Performance drops a little under load: check that nothing else was running, then the cooling.",
                                                "Les performances baissent un peu sous charge : vérifiez que rien d'autre ne tournait, puis la ventilation.")
                                            : nil))
        } else {
            result.append(Measurement(id: MetricID.performanceStability, value: nil, status: .unavailable, provenance: .derived, collectedAt: now,
                                      note: L("Too few measurements to judge the stability.", "Trop peu de mesures pour juger la stabilité.")))
        }

        // Valeurs brutes, comparées à la référence si elle existe.
        func throughput(_ id: String, _ value: Double?, _ ref: Double?, method baseMethod: String, slices: [Double]?, missing: String) {
            // Valeurs brutes dans la méthode (section Avancé, JSON) : elles servent à enrichir la table de référence.
            let method = baseMethod + (slices.map { " · " + L("slices: ", "tranches : ") + $0.map { String(Int($0.rounded())) }.joined(separator: ", ") } ?? "")
            guard let value else {
                result.append(.unavailable(id, note: missing, method: method))
                return
            }
            let text = "\(Formatters.integer(Int(value.rounded())))\(Formatters.unitSpace)GFLOPS"
            guard let ref, ref > 0 else {
                result.append(Measurement(id: id, value: .double((value * 10).rounded() / 10), unit: "GFLOPS", status: .info, method: method,
                                          collectedAt: now, display: text, detail: noReference))
                return
            }
            let ratio = value / ref
            let percent = Int((ratio * 100).rounded())
            result.append(Measurement(id: id, value: .double((value * 10).rounded() / 10), unit: "GFLOPS",
                                      status: ratio < referenceWatchRatio ? .watch : .good, provenance: .derived, method: method,
                                      collectedAt: now, display: text,
                                      detail: L("\(percent)% of the reference for this chip", "\(percent) % de la référence pour cette puce"),
                                      note: ratio < referenceWatchRatio
                                        ? L("Below the reference measured on the same chip. The reference comes from a single Mac: check the cooling and run the test again on power.",
                                            "En dessous de la référence mesurée sur la même puce. La référence vient d'un seul Mac : vérifiez la ventilation et refaites le test sur secteur.")
                                        : nil))
        }
        throughput(MetricID.performanceCPU, average(run.cpuSlices), entry?.cpuGflops,
                   method: L("Double-precision matrix multiplication (Accelerate), all cores, 30 s", "Multiplication de matrices en double précision (Accelerate), tous les cœurs, 30 s"),
                   slices: run.cpuSlices,
                   missing: L("The processor test did not produce a measurement.", "Le test du processeur n'a produit aucune mesure."))
        throughput(MetricID.performanceGPU, run.gpuSlices.flatMap(average), entry?.gpuGflops,
                   method: L("Metal compute kernel (single-precision multiply-add), 20 s", "Noyau de calcul Metal (multiplication-addition en simple précision), 20 s"),
                   slices: run.gpuSlices,
                   missing: L("Metal is not available on this Mac.", "Metal n'est pas disponible sur ce Mac."))

        if let memory = run.memoryGBps {
            result.append(Measurement(id: MetricID.performanceMemory, value: .double((memory * 10).rounded() / 10), unit: "GB/s", status: .info,
                                      method: L("Sequential copy of 256 MB buffers, 5 s", "Copie séquentielle de blocs de 256 Mo, 5 s"), collectedAt: now,
                                      display: "\(Formatters.decimal(memory))\(Formatters.unitSpace)\(L("GB/s", "Go/s"))"))
        }

        // Ventilateurs sous charge (réutilise la lecture du SMC des capteurs, spec §6.6).
        if expectsFan != false {
            let speeds = run.fanSpeeds.compactMap { $0 }
            let peakTemperature = run.temperatures.compactMap { $0 }.max()
            if speeds.isEmpty {
                if expectsFan == true {
                    result.append(.unavailable(MetricID.performanceFans, note: L("The fan speed could not be read during the test.",
                                                                               "La vitesse des ventilateurs n'a pas pu être lue pendant le test.")))
                }
            } else {
                let start = speeds.first!, peak = speeds.max()!
                let method = L("Fastest fan, read every 2 s", "Ventilateur le plus rapide, relevé toutes les 2 s")
                if peak < 1, expectsFan == true, let t = peakTemperature, t >= hotTemperature {
                    result.append(Measurement(id: MetricID.performanceFans, value: .int(0), unit: "rpm", status: .problem, method: method, collectedAt: now,
                                              display: L("Stayed stopped under load", "Restés arrêtés sous charge"),
                                              note: L("The processor reached \(Int(t.rounded())) °C and the fans did not start. Have the fans checked.",
                                                      "Le processeur a atteint \(Int(t.rounded())) °C et les ventilateurs n'ont pas démarré. Faites vérifier les ventilateurs.")))
                } else if peak < 1 {
                    result.append(Measurement(id: MetricID.performanceFans, value: .int(0), unit: "rpm", status: .info, method: method, collectedAt: now,
                                              display: L("Did not need to start", "N'ont pas eu besoin de démarrer"),
                                              detail: L("The processor stayed cool enough during the test.", "Le processeur est resté assez frais pendant le test.")))
                } else {
                    result.append(Measurement(id: MetricID.performanceFans, value: .int(Int64(peak.rounded())), unit: "rpm", status: .info, method: method,
                                              collectedAt: now,
                                              display: "\(SensorAnalysis.fanSpeedText(start)) → \(SensorAnalysis.fanSpeedText(peak))"))
                }
            }
        }

        if let peak = run.temperatures.compactMap({ $0 }).max() {
            result.append(Measurement(id: MetricID.performancePeakTemperature, value: .double((peak * 10).rounded() / 10), unit: "°C", status: .info,
                                      collectedAt: now, display: Formatters.temperature(Int(peak.rounded())),
                                      note: L("Indicative: a processor under full load can run hot without being faulty.",
                                              "Indicatif : un processeur à pleine charge peut chauffer fort sans être défectueux.")))
        }

        let power = run.powerAtStart == run.powerAtEnd ? run.powerAtStart.label
                                                       : "\(run.powerAtStart.label) → \(run.powerAtEnd.label)"
        result.append(Measurement(id: MetricID.performanceConditions, value: .int(Int64(run.duration.rounded())), unit: "s", status: .info,
                                  collectedAt: now,
                                  display: L("\(Int(run.duration.rounded())) s, \(power)", "\(Int(run.duration.rounded())) s, \(power)"),
                                  detail: entry?.source.map { L("Reference: \($0)", "Référence : \($0)") },
                                  note: run.powerAtStart == .battery || run.powerAtEnd == .battery
                                    ? L("On battery, macOS can limit performance: run the test again on the power adapter before concluding.",
                                        "Sur batterie, macOS peut limiter les performances : refaites le test sur secteur avant de conclure.")
                                    : nil))
        return result
    }
}
