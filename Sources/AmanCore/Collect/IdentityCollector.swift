import Foundation
import DiskHealthCore

/// Identité et caractéristiques (spec §6.1).
public enum IdentityCollector {
    public struct Output {
        public var measurements: [Measurement]
        /// Puce T2 lue dans `SPiBridgeDataType` (Intel uniquement).
        public var hasT2: Bool?
    }

    @available(macOS 10.15, *)
    public static func collect(profile: DeviceProfile, storageCapacity: Measurement) async -> Output {
        await runInBackground { collectSync(profile: profile, storageCapacity: storageCapacity) }
    }

    /// Version synchrone (Aman Legacy) : lance des commandes, à appeler hors du fil principal.
    public static func collectSync(profile: DeviceProfile, storageCapacity: Measurement) -> Output {
        let now = Date()
        var result: [Measurement] = []
        let model = profile.model

        // Modèle, identifiant, année de commercialisation.
        if let model {
            result.append(Measurement(id: MetricID.modelName, value: .text(model.displayName), status: .info, provenance: .derived,
                                      method: "hw.model → " + L("model table", "table des modèles"), collectedAt: now,
                                      display: model.displayName))
            result.append(Measurement(id: MetricID.modelYear, value: .int(Int64(model.year)), status: .info, provenance: .derived,
                                      method: L("model table", "table des modèles"), collectedAt: now, display: model.yearText))
        } else {
            result.append(Measurement(id: MetricID.modelName, value: .text(profile.modelIdentifier), status: .info,
                                      method: "hw.model", collectedAt: now, display: profile.modelIdentifier,
                                      detail: L("Model not recognized", "Modèle non reconnu"),
                                      note: L("This model is not in Aman Check's table yet.", "Ce modèle n'est pas encore dans la table d'Aman Check.")))
            result.append(.unavailable(MetricID.modelYear, note: L("Model not recognized.", "Modèle non reconnu.")))
        }
        result.append(Measurement(id: MetricID.modelIdentifier, value: .text(profile.modelIdentifier), status: .info,
                                  method: "sysctl hw.model", collectedAt: now, display: profile.modelIdentifier))

        // Processeur.
        let isAppleSilicon = SystemReader.isAppleSilicon
        if let brand = SystemReader.sysctlString("machdep.cpu.brand_string") {
            let pretty = prettyCPU(brand)
            result.append(Measurement(id: MetricID.chip, value: .text(brand), status: .info, method: "sysctl machdep.cpu.brand_string",
                                      collectedAt: now, display: pretty.name, detail: pretty.detail))
        } else {
            result.append(.unavailable(MetricID.chip, note: L("Could not be read.", "Lecture impossible.")))
        }

        // Cœurs.
        if isAppleSilicon, let perf = SystemReader.sysctlInt("hw.perflevel0.physicalcpu") {
            let eff = SystemReader.sysctlInt("hw.perflevel1.physicalcpu") ?? 0
            let total = perf + eff
            result.append(Measurement(id: MetricID.cpuCores, value: .int(Int64(total)), status: .info,
                                      method: "hw.perflevel0/1.physicalcpu", collectedAt: now,
                                      display: L("\(total) cores", "\(total) cœurs"),
                                      detail: L("\(perf) performance + \(eff) efficiency", "\(perf) performance + \(eff) efficacité")))
        } else if let physical = SystemReader.sysctlInt("hw.physicalcpu") {
            let logical = SystemReader.sysctlInt("hw.logicalcpu")
            result.append(Measurement(id: MetricID.cpuCores, value: .int(Int64(physical)), status: .info,
                                      method: "hw.physicalcpu / hw.logicalcpu", collectedAt: now,
                                      display: L("\(physical) cores", "\(physical) cœurs"),
                                      detail: logical.map { L("\($0) threads", "\($0) threads") }))
        }

        // Mémoire : unités binaires (32 Go = 32 × 2³⁰ octets), comme « À propos de ce Mac ».
        if let bytes = SystemReader.sysctlInt("hw.memsize"), bytes > 0 {
            let gb = Double(bytes) / 1_073_741_824
            result.append(Measurement(id: MetricID.ram, value: .int(Int64(bytes)), unit: "B", status: .info, method: "sysctl hw.memsize",
                                      collectedAt: now,
                                      display: "\(Formatters.decimal(gb.rounded()))\(Formatters.unitSpace)\(L("GB", "Go"))",
                                      detail: isAppleSilicon ? L("Unified memory", "Mémoire unifiée") : nil))
        }

        result.append(storageCapacity)

        // macOS installé et macOS maximal.
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        let build = SystemReader.sysctlString("kern.osversion")
        let releaseName = MacOSRelease.name(v.majorVersion).replacingOccurrences(of: "macOS \(v.majorVersion) ", with: "")
        result.append(Measurement(id: MetricID.macOS, value: .text(version), status: .info, method: "ProcessInfo.operatingSystemVersion",
                                  collectedAt: now, display: "macOS \(version)",
                                  detail: [releaseName == "macOS \(v.majorVersion)" ? nil : releaseName, build.map { "build \($0)" }]
                                      .compactMap { $0 }.joined(separator: " · ")))
        result.append(macOSMax(model, now: now))

        // N° de série : 4 derniers caractères seulement, jamais le numéro complet dans le rapport.
        if let serial = SystemReader.serialNumber, serial.count >= 4 {
            let last4 = String(serial.suffix(4))
            result.append(Measurement(id: MetricID.serial, value: .text(last4), status: .info, method: "IOPlatformSerialNumber",
                                      collectedAt: now, display: "••••\(last4)",
                                      detail: L("Last 4 characters", "4 derniers caractères"),
                                      note: [L("The buyer can check the full number on checkcoverage.apple.com.",
                                               "L'acheteur peut vérifier le numéro complet sur checkcoverage.apple.com."),
                                             SerialNumberText.configurationNote(serialLength: serial.count)].compactMap { $0 }.joined(separator: " ")))
        } else {
            result.append(.unavailable(MetricID.serial, note: L("Could not be read.", "Lecture impossible.")))
        }

        // Graphisme et écran (system_profiler : pas d'API publique équivalente).
        let displays = Shell.runSync("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-json"])
        if let displays { DiagnosticLog.shared.record("SPDisplaysDataType", displays.stdout) }
        let parsed = DisplaysParser.parse(displays?.stdout)
        if let gpu = parsed.gpu {
            result.append(Measurement(id: MetricID.gpu, value: .text(gpu.name), status: .info, method: "system_profiler SPDisplaysDataType",
                                      collectedAt: now, display: gpu.name, detail: gpu.detail))
        } else {
            result.append(.unavailable(MetricID.gpu, note: L("Could not be read.", "Lecture impossible.")))
        }
        if let screen = parsed.builtInDisplay {
            result.append(Measurement(id: MetricID.display, value: .text(screen.raw), status: .info,
                                      method: "system_profiler SPDisplaysDataType", collectedAt: now,
                                      display: screen.name, detail: screen.detail))
        }

        // Puce de sécurité.
        var hasT2: Bool?
        if isAppleSilicon {
            result.append(Measurement(id: MetricID.securityChip, value: .text("apple-silicon"), status: .info, collectedAt: now,
                                      display: L("Apple silicon (Secure Enclave)", "Puce Apple (Secure Enclave)")))
        } else {
            let bridge = Shell.runSync("/usr/sbin/system_profiler", ["SPiBridgeDataType", "-json"])
            if let bridge { DiagnosticLog.shared.record("SPiBridgeDataType", bridge.stdout) }
            let name = DisplaysParser.bridgeModelName(bridge?.stdout)
            hasT2 = name.map { $0.contains("T2") }
            if let name {
                result.append(Measurement(id: MetricID.securityChip, value: .text(name), status: .info,
                                          method: "system_profiler SPiBridgeDataType", collectedAt: now,
                                          display: hasT2 == true ? L("Apple T2 chip", "Puce Apple T2") : L("None", "Aucune")))
            } else {
                // Lecture impossible ≠ « Aucune » : on ne sait pas.
                result.append(.unavailable(MetricID.securityChip, note: L("Could not be read.", "Lecture impossible."),
                                           method: "system_profiler SPiBridgeDataType"))
            }
        }
        return Output(measurements: result, hasT2: hasT2)
    }

    public static func macOSMax(_ model: MacModel?, now: Date) -> Measurement {
        guard let model else {
            return .unavailable(MetricID.macOSMax, note: L("Model not recognized.", "Modèle non reconnu."))
        }
        let method = L("model table · Apple compatibility lists", "table des modèles · listes de compatibilité Apple")
        if let last = model.lastMacOS {
            let isLatest = last >= MacOSRelease.latestKnown
            let detail: String
            if isLatest && model.chip != .appleSilicon {
                detail = L("Latest version, and the last one for Intel Macs", "Version actuelle, et dernière pour les Mac Intel")
            } else if isLatest {
                detail = L("Latest version", "Version actuelle")
            } else {
                detail = L("Will not receive \(MacOSRelease.name(MacOSRelease.latestKnown))", "Ne recevra pas \(MacOSRelease.name(MacOSRelease.latestKnown))")
            }
            return Measurement(id: MetricID.macOSMax, value: .int(Int64(last)), status: .info, provenance: .derived, method: method, collectedAt: now,
                               display: MacOSRelease.name(last), detail: detail)
        }
        return Measurement(id: MetricID.macOSMax, value: .int(Int64(MacOSRelease.latestKnown)), status: .info, provenance: .derived, method: method,
                           collectedAt: now, display: MacOSRelease.name(MacOSRelease.latestKnown),
                           detail: L("Still supported by Apple", "Toujours pris en charge par Apple"))
    }

    /// « Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz » → « Intel Core i9-9980HK », « 2,4 GHz ».
    public static func prettyCPU(_ brand: String) -> (name: String, detail: String?) {
        var name = brand.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
        var detail: String?
        if let at = name.range(of: "@") {
            let freq = name[at.upperBound...].trimmingCharacters(in: .whitespaces)
            if let ghz = Double(freq.replacingOccurrences(of: "GHz", with: "")) {
                detail = "\(Formatters.decimal(ghz))\(Formatters.unitSpace)GHz"
            }
            name = String(name[..<at.lowerBound])
        }
        name = name.replacingOccurrences(of: " CPU", with: "")
        name = name.split(separator: " ").joined(separator: " ")
        return (name, detail)
    }
}

/// Lecture tolérante de `system_profiler SPDisplaysDataType -json`.
public enum DisplaysParser {
    public struct GPU { public let name: String; public let detail: String? }
    public struct Screen { public let name: String; public let detail: String?; public let raw: String }

    public static func parse(_ json: String?) -> (gpu: GPU?, builtInDisplay: Screen?) {
        guard let json, let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let items = root["SPDisplaysDataType"] as? [[String: Any]] else { return (nil, nil) }
        var names: [String] = []
        var details: [String] = []
        var screen: Screen?
        for gpu in items {
            if let model = gpu["sppci_model"] as? String {
                var label = model
                // TODO: à valider sur machine réelle (Apple Silicon) : « sppci_cores ».
                if let cores = gpu["sppci_cores"] as? String, let n = Int(cores) {
                    label += " · " + L("\(n)-core GPU", "GPU \(n) cœurs")
                }
                names.append(label)
                if let vram = gpu["spdisplays_vram"] as? String, gpu["spdisplays_vram_shared"] == nil {
                    details.append("\(model) : \(vram.replacingOccurrences(of: "GB", with: L("GB", "Go")).replacingOccurrences(of: "MB", with: L("MB", "Mo")))")
                }
            }
            for display in gpu["spdisplays_ndrvs"] as? [[String: Any]] ?? [] {
                guard (display["spdisplays_connection_type"] as? String) == "spdisplays_internal" else { continue }
                let native = (display["spdisplays_pixelresolution"] as? String)
                    .map { $0.replacingOccurrences(of: "spdisplays_", with: "") } ?? ""
                let isRetina = native.lowercased().contains("retina") || (display["spdisplays_display_type"] as? String)?.contains("retina") == true
                let pixels = native.replacingOccurrences(of: "Retina", with: "").replacingOccurrences(of: "x", with: " × ")
                var parts: [String] = []
                if let res = display["_spdisplays_resolution"] as? String, let at = res.range(of: "@ ") {
                    let hz = res[at.upperBound...].replacingOccurrences(of: "Hz", with: "")
                    if let value = Double(hz) { parts.append("\(Formatters.decimal(value))\(Formatters.unitSpace)Hz") }
                }
                let name = (isRetina ? "Retina " : "") + (pixels.isEmpty ? L("Built-in", "Intégré") : pixels)
                screen = Screen(name: name, detail: parts.isEmpty ? nil : parts.joined(separator: " · "), raw: native)
            }
        }
        guard !names.isEmpty else { return (nil, screen) }
        return (GPU(name: names.joined(separator: " + "), detail: details.isEmpty ? nil : details.joined(separator: " · ")), screen)
    }

    /// « Puce de sécurité T2 d'Apple » (nom localisé) : on cherche « T2 ».
    public static func bridgeModelName(_ json: String?) -> String? {
        guard let json, let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let items = root["SPiBridgeDataType"] as? [[String: Any]] else { return nil }
        return items.compactMap { $0["ibridge_model_name"] as? String }.first
    }
}
