import Foundation

/// Verrouillages, SIP, FileVault, machine virtuelle (spec §6.4). Aucune élévation de droits.
public enum SecurityCollector {
    @available(macOS 10.15, *)
    public static func collect(profile: DeviceProfile) async -> [Measurement] {
        await runInBackground { collectSync(profile: profile) }
    }

    /// Version synchrone (Aman Legacy) : les sept commandes tournent en parallèle, comme avant ;
    /// à appeler hors du fil principal.
    public static func collectSync(profile: DeviceProfile) -> [Measurement] {
        let results = Shell.runAllSync([
            ("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"]),
            ("/usr/bin/profiles", ["status", "-type", "enrollment"]),
            ("/usr/bin/profiles", ["list"]),
            ("/usr/bin/csrutil", ["status"]),
            ("/usr/bin/fdesetup", ["status"]),
            // Compte Apple connecté : export plist du domaine MobileMeAccounts. Sa sortie contient l'identifiant du compte :
            // elle n'est ni journalisée ni conservée, seuls le nombre de comptes et l'état de Localiser en sont tirés.
            ("/usr/bin/defaults", ["export", "MobileMeAccounts", "-"]),
            // Comptes utilisateurs locaux : la lecture du compte Apple ne couvre que la session en cours.
            ("/usr/bin/dscl", [".", "-list", "/Users", "UniqueID"])
        ])
        let (hw, enr, list, csr, fde, mm, dscl) = (results[0], results[1], results[2], results[3], results[4], results[5], results[6])

        // Le numéro de série n'entre jamais dans le journal de diagnostic (masqué par `DiagnosticLog.record`).
        if let hw { DiagnosticLog.shared.record("SPHardwareDataType", hw.stdout) }
        if let enr { DiagnosticLog.shared.record("profiles status", enr.stdout + enr.stderr) }
        if let csr { DiagnosticLog.shared.record("csrutil status", csr.stdout) }

        let lock = SecurityAnalysis.activationLock(hardwareJSON: hw.map { Data($0.stdout.utf8) }, chip: profile.chip)
        let domainMissing = mm.map { $0.exitCode != 0 && $0.stderr.lowercased().contains("does not exist") } ?? false
        let account = SecurityAnalysis.appleAccount(mobileMePlist: mm.flatMap { $0.exitCode == 0 ? Data($0.stdout.utf8) : nil },
                                                    domainMissing: domainMissing, chip: profile.chip,
                                                    activationLockOff: lock.status == .good,
                                                    localUserCount: SecurityAnalysis.localUserCount(dsclOutput: dscl.flatMap { $0.exitCode == 0 ? $0.stdout : nil }))
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
