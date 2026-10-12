import Foundation
import CoreWLAN
import IOBluetooth
import AmanCore
import DiskHealthCore

/// Batterie (spec §6.2) : lecture IOKit + état déclaré par macOS, analyse dans AmanCore.
enum BatteryCollector {
    static func collect(profile: DeviceProfile) async -> [Measurement] {
        // Profil simulé de Mac de bureau : pas de batterie, même si la machine de développement en a une.
        if profile.isSimulated && !profile.hasBattery { return [] }
        guard let props = SystemReader.batteryProperties() else { return [] }
        let registry = BatteryRegistry(properties: props)
        DiagnosticLog.shared.record("AppleSmartBattery", String(describing: registry))
        let sp = await Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"])
        if let sp { DiagnosticLog.shared.record("SPPowerDataType", sp.stdout) }
        let power = sp.flatMap { PowerProfile(systemProfilerJSON: Data($0.stdout.utf8)) }
        return BatteryAnalysis.analyze(registry: registry, power: power, ratedCyclesFromModel: profile.model?.ratedBatteryCycles)
    }
}

/// Verrouillages, SIP, FileVault, machine virtuelle (spec §6.4). Aucune élévation de droits.
enum SecurityCollector {
    static func collect(profile: DeviceProfile) async -> [Measurement] {
        async let hardware = Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"])
        async let enrollment = Shell.run("/usr/bin/profiles", ["status", "-type", "enrollment"])
        async let profilesList = Shell.run("/usr/bin/profiles", ["list"])
        async let csrutil = Shell.run("/usr/bin/csrutil", ["status"])
        async let fdesetup = Shell.run("/usr/bin/fdesetup", ["status"])
        // Compte Apple connecté : export plist du domaine MobileMeAccounts. Sa sortie contient l'identifiant du compte :
        // elle n'est ni journalisée ni conservée, seuls le nombre de comptes et l'état de Localiser en sont tirés.
        async let mobileMe = Shell.run("/usr/bin/defaults", ["export", "MobileMeAccounts", "-"])
        let (hw, enr, list, csr, fde, mm) = await (hardware, enrollment, profilesList, csrutil, fdesetup, mobileMe)

        // Le numéro de série n'entre jamais dans le journal de diagnostic (masqué par `DiagnosticLog.record`).
        if let hw { DiagnosticLog.shared.record("SPHardwareDataType", hw.stdout) }
        if let enr { DiagnosticLog.shared.record("profiles status", enr.stdout + enr.stderr) }
        if let csr { DiagnosticLog.shared.record("csrutil status", csr.stdout) }

        let lock = SecurityAnalysis.activationLock(hardwareJSON: hw.map { Data($0.stdout.utf8) }, chip: profile.chip)
        let domainMissing = mm.map { $0.exitCode != 0 && $0.stderr.lowercased().contains("does not exist") } ?? false
        let account = SecurityAnalysis.appleAccount(mobileMePlist: mm.flatMap { $0.exitCode == 0 ? Data($0.stdout.utf8) : nil },
                                                    domainMissing: domainMissing, chip: profile.chip,
                                                    activationLockOff: lock.status == .good)
        DiagnosticLog.shared.log("compte apple", "\(account.displayText) [\(account.status.rawValue)]")

        return [
            lock,
            account,
            SecurityAnalysis.mdm(enrollmentOutput: enr?.stdout, exitCode: enr?.exitCode),
            SecurityAnalysis.firmwarePassword(chip: profile.chip),
            SecurityAnalysis.sip(csrutilOutput: csr?.stdout),
            SecurityAnalysis.fileVault(fdesetupOutput: fde?.stdout),
            SecurityAnalysis.configurationProfiles(listOutput: list.map { $0.stdout + $0.stderr }),
            SecurityAnalysis.virtualMachine(hvVmmPresent: SystemReader.sysctlInt("kern.hv_vmm_present"))
        ]
    }
}

/// Wi-Fi et Bluetooth (spec §6.5). Le Wi-Fi est testé sans lire les noms de réseaux
/// (pas d'autorisation de localisation) : interface présente, allumée, scan non vide.
enum ConnectivityCollector {
    static func collect() async -> [Measurement] {
        async let wifi = wifiMeasurement()
        async let bt = bluetoothMeasurement()
        return [await wifi, await bt]
    }

    /// `IOBluetoothHostController.default()` peut bloquer indéfiniment (attente d'autorisation Bluetooth jamais
    /// affichée, démon qui ne répond pas) : lecture sur un fil dédié avec un délai de garde, comme `Shell.run`.
    /// Au-delà du délai, la mesure est « à vérifier soi-même », jamais un faux verdict.
    private static let bluetoothTimeout: TimeInterval = 5

    private static func bluetoothMeasurement() async -> Measurement {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var continuation: CheckedContinuation<Measurement?, Never>?
            func resume(_ value: Measurement?) {
                lock.lock(); defer { lock.unlock() }
                continuation?.resume(returning: value)
                continuation = nil
            }
        }
        let box = Box()
        let result: Measurement? = await withCheckedContinuation { continuation in
            box.continuation = continuation
            Thread.detachNewThread { box.resume(readBluetooth()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + bluetoothTimeout) { box.resume(nil) }
        }
        if let result { return result }
        DiagnosticLog.shared.log("bluetooth", "délai dépassé (\(Int(bluetoothTimeout)) s) : IOBluetoothHostController ne répond pas")
        return Measurement(id: MetricID.bluetooth, value: nil, status: .manualRequired, method: "IOBluetooth · IOBluetoothHostController",
                           display: L("Check manually", "À vérifier soi-même"),
                           note: L("Bluetooth did not answer in time. Open the Bluetooth menu and check that it is on and sees nearby devices.",
                                   "Le Bluetooth n'a pas répondu à temps. Ouvrez le menu Bluetooth et vérifiez qu'il est actif et voit des appareils à proximité."))
    }

    private static func wifiMeasurement() async -> Measurement {
        let id = MetricID.wifi
        let method = "CoreWLAN · CWWiFiClient"
        guard let interface = CWWiFiClient.shared().interface() else {
            return Measurement(id: id, value: nil, status: .unavailable, method: method,
                               note: L("No Wi-Fi interface found.", "Aucune interface Wi-Fi détectée."))
        }
        guard interface.powerOn() else {
            return Measurement(id: id, value: .text("off"), status: .manualRequired, method: method,
                               display: L("Turned off", "Désactivé"),
                               note: L("Turn Wi-Fi on and run the check again.", "Activez le Wi-Fi puis relancez le contrôle."))
        }
        // Le scan peut prendre quelques secondes : hors du fil principal.
        let count: Int? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let networks = try? interface.scanForNetworks(withSSID: nil)
                continuation.resume(returning: networks?.count)
            }
        }
        DiagnosticLog.shared.log("wifi", "scan : \(count.map(String.init) ?? "échec")")
        guard let count else {
            return Measurement(id: id, value: .text("scan-failed"), status: .manualRequired, method: method + " · scanForNetworks",
                               display: L("Scan failed", "Recherche impossible"),
                               note: L("Open the Wi-Fi menu and check that networks appear.", "Ouvrez le menu Wi-Fi et vérifiez que des réseaux apparaissent."))
        }
        if count == 0 {
            return Measurement(id: id, value: .int(0), status: .watch, method: method + " · scanForNetworks",
                               display: L("No network found", "Aucun réseau trouvé"),
                               note: L("Normal far from any network. Otherwise, check the Wi-Fi menu.", "Normal loin de tout réseau. Sinon, vérifiez le menu Wi-Fi."))
        }
        return Measurement(id: id, value: .int(Int64(count)), status: .good, method: method + " · scanForNetworks",
                           display: L("Working", "Fonctionnel"),
                           detail: L("\(count) networks detected nearby", "\(count) réseaux détectés à proximité"))
    }

    private static func readBluetooth() -> Measurement {
        let id = MetricID.bluetooth
        let method = "IOBluetooth · IOBluetoothHostController"
        guard let controller = IOBluetoothHostController.default(), controller.addressAsString() != nil else {
            return Measurement(id: id, value: nil, status: .unavailable, method: method,
                               note: L("No Bluetooth controller found.", "Aucun contrôleur Bluetooth détecté."))
        }
        let isOn = controller.powerState == kBluetoothHCIPowerStateON
        if !isOn {
            return Measurement(id: id, value: .text("off"), status: .manualRequired, method: method,
                               display: L("Turned off", "Désactivé"),
                               note: L("Turn Bluetooth on and run the check again.", "Activez le Bluetooth puis relancez le contrôle."))
        }
        return Measurement(id: id, value: .text("on"), status: .good, method: method,
                           display: L("Working", "Fonctionnel"), detail: L("Controller present and on", "Contrôleur présent et allumé"))
    }
}
