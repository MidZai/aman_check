import Foundation
import DiskHealthCore

/// Clés de `AppleSmartBattery` (IOKit) utiles au contrôle. Toutes optionnelles.
public struct BatteryRegistry: Sendable, Equatable {
    public var cycleCount: Int?
    public var designCapacity: Int?
    public var maxCapacity: Int?
    public var appleRawMaxCapacity: Int?
    public var nominalChargeCapacity: Int?
    /// Cycles pour lesquels la batterie est conçue, déclarés par la batterie elle-même.
    public var designCycleCount: Int?
    public var isCharging: Bool?
    public var externalConnected: Bool?
    /// Centièmes de degré Celsius sur les Mac Intel. TODO: à valider sur Apple Silicon.
    public var temperature: Int?
    public var permanentFailureStatus: Int?
    public var batteryInstalled: Bool?

    public init() {}

    /// Depuis `IORegistryEntryCreateCFProperties` (ou un plist `ioreg -a` en test).
    public init(properties p: [String: Any]) {
        func int(_ key: String) -> Int? {
            if let n = p[key] as? NSNumber { return n.intValue }
            return p[key] as? Int
        }
        func bool(_ key: String) -> Bool? {
            if let b = p[key] as? Bool { return b }
            if let n = p[key] as? NSNumber { return n.boolValue }
            return nil
        }
        cycleCount = int("CycleCount")
        designCapacity = int("DesignCapacity")
        maxCapacity = int("MaxCapacity")
        appleRawMaxCapacity = int("AppleRawMaxCapacity")
        nominalChargeCapacity = int("NominalChargeCapacity")
        designCycleCount = int("DesignCycleCount9C")
        isCharging = bool("IsCharging")
        externalConnected = bool("ExternalConnected")
        temperature = int("Temperature")
        permanentFailureStatus = int("PermanentFailureStatus")
        batteryInstalled = bool("BatteryInstalled")
    }
}

/// Ce que macOS déclare dans `system_profiler SPPowerDataType -json`.
public struct PowerProfile: Sendable, Equatable {
    /// « Good », « Normal », « Service Recommended »… (valeur brute, non traduite).
    public var condition: String?
    /// « Capacité maximale » affichée par macOS (Apple Silicon et macOS récents). Absente sur ce MBP Intel.
    public var maximumCapacityPercent: Int?
    public var cycleCount: Int?

    public init(condition: String? = nil, maximumCapacityPercent: Int? = nil, cycleCount: Int? = nil) {
        self.condition = condition
        self.maximumCapacityPercent = maximumCapacityPercent
        self.cycleCount = cycleCount
    }

    public init?(systemProfilerJSON data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        guard let battery = items.first(where: { $0["sppower_battery_health_info"] != nil }),
              let health = battery["sppower_battery_health_info"] as? [String: Any] else {
            self.init()
            return
        }
        self.init()
        condition = health["sppower_battery_health"] as? String
        cycleCount = (health["sppower_battery_cycle_count"] as? NSNumber)?.intValue
        // TODO: à valider sur machine réelle (Apple Silicon) : clé et format « 87% ».
        if let text = health["sppower_battery_health_maximum_capacity"] as? String {
            maximumCapacityPercent = Int(text.filter(\.isNumber))
        } else if let n = health["sppower_battery_health_maximum_capacity"] as? NSNumber {
            maximumCapacityPercent = n.intValue
        }
    }
}

/// Analyse de la batterie (spec §6.2) : méthodes multiples, contrôle d'unité, recoupement.
/// Jamais de pourcentage inventé : en cas de doute, « Non disponible » ou « Vérification manuelle ».
public enum BatteryAnalysis {
    public struct Thresholds: Sendable {
        public var good = 80
        public var watch = 70
        public init() {}
    }

    /// Batterie absente (Mac de bureau) : la section disparaît, elle n'est pas grisée.
    public static func analyze(registry: BatteryRegistry?, power: PowerProfile?, ratedCyclesFromModel: Int?,
                               thresholds: Thresholds = Thresholds(), now: Date = Date()) -> [Measurement] {
        guard let r = registry, r.batteryInstalled != false else { return [] }
        var result: [Measurement] = []

        let condition = conditionMeasurement(power?.condition, permanentFailure: r.permanentFailureStatus, now: now)
        let health = healthMeasurement(r, power: power, condition: condition?.status, thresholds: thresholds, now: now)
        result.append(health)
        result.append(cyclesMeasurement(r, power: power, ratedCyclesFromModel: ratedCyclesFromModel, now: now))
        if let condition { result.append(condition) }

        if let design = r.designCapacity, design > 0 {
            result.append(Measurement(id: MetricID.batteryDesignCapacity, value: .int(Int64(design)), unit: "mAh", status: .info,
                                      method: "DesignCapacity", collectedAt: now, display: mAh(design)))
        }
        if let (current, source) = currentCapacity(r) {
            result.append(Measurement(id: MetricID.batteryMaxCapacity, value: .int(Int64(current)), unit: "mAh", status: .info,
                                      method: source, collectedAt: now, display: mAh(current)))
        }
        if let external = r.externalConnected {
            let text: String
            if external {
                text = r.isCharging == true ? L("Charging", "En charge") : L("On power adapter", "Sur secteur")
            } else {
                text = L("On battery", "Sur batterie")
            }
            result.append(Measurement(id: MetricID.batteryCharging, value: .text(text), status: .info,
                                      method: "ExternalConnected / IsCharging", collectedAt: now, display: text))
        }
        if let t = r.temperature, t > 0 {
            // Centièmes de degré sur Intel (3117 = 31,17 °C). Hors plage plausible : non affiché.
            let celsius = Double(t) / 100
            if (5...80).contains(celsius) {
                result.append(Measurement(id: MetricID.batteryTemperature, value: .double(celsius), unit: "°C", status: .info,
                                          method: "Temperature / 100", collectedAt: now,
                                          display: Formatters.temperature(Int(celsius.rounded()))))
            }
        }
        return result
    }

    /// Capacité maximale actuelle en mAh, avec la clé utilisée.
    /// Ordre de préférence (spec) : NominalChargeCapacity → AppleRawMaxCapacity → MaxCapacity.
    /// `MaxCapacity ≤ 150` est un pourcentage (Apple Silicon), pas des mAh : écarté.
    static func currentCapacity(_ r: BatteryRegistry) -> (Int, String)? {
        if let v = r.nominalChargeCapacity, v > 150 { return (v, "NominalChargeCapacity") }
        if let v = r.appleRawMaxCapacity, v > 150 { return (v, "AppleRawMaxCapacity") }
        if let v = r.maxCapacity, v > 150 { return (v, "MaxCapacity") }
        return nil
    }

    static func healthMeasurement(_ r: BatteryRegistry, power: PowerProfile?, condition: CheckStatus?,
                                  thresholds: Thresholds, now: Date) -> Measurement {
        let id = MetricID.batteryHealth
        guard let design = r.designCapacity, design > 0 else {
            return .unavailable(id, note: L("The battery does not report its original capacity.", "La batterie n'indique pas sa capacité d'origine."))
        }
        guard let (current, source) = currentCapacity(r) else {
            return .unavailable(id, note: L("The battery does not report its current capacity in mAh.", "La batterie n'indique pas sa capacité actuelle en mAh."))
        }
        let ratio = Double(current) / Double(design)
        let method = "\(source) / DesignCapacity = \(current) / \(design) mAh"
        guard (0.3...1.2).contains(ratio) else {
            return .unavailable(id, note: L("The values read are inconsistent (\(current) / \(design) mAh).",
                                             "Les valeurs lues sont incohérentes (\(current) / \(design) mAh)."), method: method)
        }
        let rawPercent = ratio * 100
        let percent = Int(min(100, rawPercent).rounded())
        var notes: [String] = []
        if rawPercent > 100 {
            notes.append(L("Measured above 100% (\(Int(rawPercent.rounded()))%): shown as 100%.",
                           "Mesurée au-dessus de 100 % (\(Int(rawPercent.rounded())) %) : affichée à 100 %."))
        }

        var status: CheckStatus = percent >= thresholds.good ? .good : (percent >= thresholds.watch ? .watch : .problem)
        if condition == .problem { status = .problem }

        // Recoupement avec la « Capacité maximale » affichée par macOS : il ne peut que dégrader un statut
        // bon ou à surveiller ; un problème (« Service recommandé ») reste un problème.
        if let macOS = power?.maximumCapacityPercent {
            if abs(macOS - percent) > 5 {
                if status != .problem { status = .manualRequired }
                notes.append(L("macOS shows \(macOS)% while the battery reports \(percent)%: check in System Settings > Battery.",
                               "macOS affiche \(macOS) % alors que la batterie indique \(percent) % : vérifiez dans Réglages Système > Batterie."))
            } else {
                notes.append(L("Consistent with macOS (\(macOS)%).", "Cohérent avec macOS (\(macOS) %)."))
            }
        }

        return Measurement(id: id, value: .int(Int64(percent)), unit: "%", status: status, method: method, collectedAt: now,
                           display: "\(percent)\(Formatters.unitSpace)%",
                           detail: L("of its original capacity", "de sa capacité d'origine"),
                           note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    static func cyclesMeasurement(_ r: BatteryRegistry, power: PowerProfile?, ratedCyclesFromModel: Int?, now: Date) -> Measurement {
        let id = MetricID.batteryCycles
        guard let cycles = r.cycleCount ?? power?.cycleCount, cycles >= 0 else {
            return .unavailable(id, note: L("The battery does not report its cycle count.", "La batterie n'indique pas son nombre de cycles."))
        }
        let rated = r.designCycleCount.flatMap { $0 > 0 ? $0 : nil } ?? ratedCyclesFromModel
        let source = r.designCycleCount != nil ? "DesignCycleCount9C" : (ratedCyclesFromModel != nil ? L("model table", "table des modèles") : nil)
        let detail: String
        let status: CheckStatus
        if let rated {
            detail = L("out of \(Formatters.integer(rated)) planned for this battery", "sur \(Formatters.integer(rated)) prévus pour cette batterie")
            status = cycles >= rated ? .watch : .good
        } else {
            // Sans nombre prévu, le compte ne peut pas être jugé : une information, pas un point vert.
            detail = L("rated count unknown for this model", "nombre prévu inconnu pour ce modèle")
            status = .info
        }
        return Measurement(id: id, value: .int(Int64(cycles)), unit: L("cycles", "cycles"), status: status,
                           method: "CycleCount" + (source.map { " · \(L("rated", "prévu")) : \($0)" } ?? ""),
                           collectedAt: now, display: Formatters.integer(cycles), detail: detail)
    }

    /// État déclaré par macOS. Valeurs connues d'Apple ; toute autre valeur demande une vérification.
    static func conditionMeasurement(_ raw: String?, permanentFailure: Int?, now: Date) -> Measurement? {
        let id = MetricID.batteryCondition
        if let failure = permanentFailure, failure != 0 {
            return Measurement(id: id, value: .int(Int64(failure)), status: .problem, method: "PermanentFailureStatus",
                               collectedAt: now, display: L("Battery fault", "Défaut de batterie"),
                               note: L("The battery reports a permanent failure.", "La batterie signale une défaillance permanente."))
        }
        guard let raw, !raw.isEmpty else { return nil }
        let key = raw.lowercased()
        let (text, status): (String, CheckStatus)
        switch key {
        case "good", "normal":
            (text, status) = (L("Normal", "Normale"), .good)
        case "fair":
            (text, status) = (L("Fair", "Correcte"), .watch)
        case "service recommended", "check battery", "replace soon", "replace now", "poor":
            (text, status) = (L("Service recommended", "Service recommandé"), .problem)
        default:
            // Valeur non prévue : affichée telle quelle, à vérifier.
            (text, status) = (raw, .manualRequired)
        }
        return Measurement(id: id, value: .text(raw), status: status, method: "SPPowerDataType · sppower_battery_health",
                           collectedAt: now, display: text)
    }

    private static func mAh(_ v: Int) -> String { "\(Formatters.integer(v))\(Formatters.unitSpace)mAh" }
}
