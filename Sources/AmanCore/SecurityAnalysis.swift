import Foundation
import DiskHealthCore

/// Verrouillages et protection du système (spec §6.4). Verdicts prudents : jamais de vert par défaut.
/// Les quatre états affichables : Aucun signal détecté · Signal détecté · Vérification impossible ·
/// Vérification complémentaire nécessaire.
public enum SecurityAnalysis {

    // MARK: Textes partagés

    public static var noSignal: String { L("No signal detected", "Aucun signal détecté") }
    public static var signalDetected: String { L("Signal detected", "Signal détecté") }
    public static var cannotCheck: String { L("Cannot be checked", "Vérification impossible") }
    /// Même formule que la pastille « Vérification manuelle » : l'app ne peut pas conclure, l'utilisateur doit regarder lui-même.
    public static var checkYourself: String { L("Check manually", "À vérifier soi-même") }
    public static var furtherCheck: String { L("Further check needed", "Vérification complémentaire nécessaire") }
    /// Verrouillage d'activation : dit explicitement « verrou » pour ne pas être lu comme « aucun compte iCloud ».
    public static var lockOff: String { L("Lock off", "Verrou désactivé") }
    public static var lockOn: String { L("Lock on", "Verrou activé") }

    /// Conseil avant achat, toujours affiché sous le verrouillage d'activation.
    public static var activationLockAdvice: String {
        L("Before buying, ask the seller to sign out of iCloud, turn off Find My and erase the Mac, then make sure Setup Assistant asks for no Apple Account.",
          "Avant l'achat, demandez au vendeur de se déconnecter d'iCloud, de désactiver Localiser et d'effacer le Mac, puis vérifiez que l'assistant de configuration n'exige aucun identifiant.")
    }

    public static var mdmLimit: String {
        L("A check from the current session does not replace Setup Assistant after erasing the Mac.",
          "Un contrôle depuis la session actuelle ne remplace pas la vérification de l'assistant de configuration après effacement.")
    }

    // MARK: Verrouillage d'activation

    /// `system_profiler SPHardwareDataType -json` → `activation_lock_status`.
    /// Valeur observée sur MacBookPro16,1 (T2, macOS 26.4.1) : « activation_lock_disabled ».
    public static func activationLock(hardwareJSON data: Data?, chip: ChipFamily?, now: Date = Date()) -> Measurement {
        let id = MetricID.activationLock
        let method = "system_profiler SPHardwareDataType · activation_lock_status"
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hw = (root["SPHardwareDataType"] as? [[String: Any]])?.first else {
            return Measurement(id: id, value: nil, status: .manualRequired, method: method, collectedAt: now,
                               display: checkYourself, note: activationLockAdvice)
        }
        guard let raw = hw["activation_lock_status"] as? String else {
            let reason = chip == .intel
                ? L("This Mac has neither a T2 chip nor Apple silicon: macOS does not report this status.",
                    "Ce Mac n'a ni puce T2 ni puce Apple : macOS n'indique pas ce statut.")
                : L("macOS did not report this status.", "macOS n'a pas indiqué ce statut.")
            return Measurement(id: id, value: nil, status: chip == .intel ? .unavailable : .manualRequired, method: method,
                               collectedAt: now, display: chip == .intel ? cannotCheck : checkYourself,
                               note: reason + " " + activationLockAdvice)
        }
        let key = raw.lowercased()
        if key.hasSuffix("_disabled") || key == "disabled" {
            return Measurement(id: id, value: .text(raw), status: .good, method: method, collectedAt: now,
                               display: lockOff,
                               detail: L("macOS reports Activation Lock as off. This says nothing about an Apple Account still signed in: see “Apple Account signed in”.",
                                         "macOS indique que le verrouillage d'activation est désactivé. Cela ne dit rien d'un compte Apple encore connecté : voir « Compte Apple connecté »."),
                               note: activationLockAdvice)
        }
        if key.hasSuffix("_enabled") || key == "enabled" {
            return Measurement(id: id, value: .text(raw), status: .problem, method: method, collectedAt: now,
                               display: lockOn,
                               detail: L("Activation Lock is on: after an erase, this Mac asks for the owner's Apple Account.",
                                         "Le verrouillage d'activation est activé : après effacement, ce Mac exigera le compte Apple du propriétaire."),
                               note: L("This is expected while the seller is still signed in to iCloud with Find My on. It must be turned off before the sale. ",
                                       "C'est normal tant que le vendeur est connecté à iCloud avec Localiser actif. Il doit être désactivé avant la vente. ") + activationLockAdvice)
        }
        return Measurement(id: id, value: .text(raw), status: .manualRequired, method: method, collectedAt: now,
                           display: furtherCheck, note: activationLockAdvice)
    }

    // MARK: Compte Apple connecté

    /// Lecture du domaine de préférences `MobileMeAccounts` (export plist, sans droits administrateur).
    /// Seuls le nombre de comptes et l'état de « Localiser mon Mac » sont conservés : jamais l'identifiant du compte.
    ///
    /// Le verrouillage d'activation peut être signalé désactivé alors qu'un compte est connecté avec Localiser actif
    /// (sur Mac Intel T2, il ne s'arme qu'avec le démarrage sécurisé en « Sécurité maximale ») : la mesure le précise.
    /// `localUserCount` : comptes utilisateurs locaux du Mac (`dscl . -list /Users UniqueID`, UID ≥ 501) ;
    /// nil si illisible. La lecture ne couvre que la session en cours : avec plusieurs comptes, ou un
    /// nombre illisible, « aucun compte » ne peut pas être vert.
    public static func appleAccount(mobileMePlist data: Data?, domainMissing: Bool, chip: ChipFamily?,
                                    activationLockOff: Bool, localUserCount: Int?, now: Date = Date()) -> Measurement {
        let id = MetricID.appleAccount
        let method = "defaults export MobileMeAccounts · Accounts, FIND_MY_MAC · dscl . -list /Users UniqueID"
        let decisive = L("The decisive check remains Setup Assistant after erasing: it must ask for no Apple Account.",
                         "La vérification décisive reste l'assistant de configuration après effacement : il ne doit exiger aucun compte Apple.")
        let unreadable = Measurement(id: id, value: nil, status: .manualRequired, method: method, collectedAt: now,
                                     display: checkYourself,
                                     note: L("Could not be read. Open System Settings: the Apple Account appears at the top of the sidebar.",
                                             "Lecture impossible. Ouvrez Réglages Système : le compte Apple apparaît en haut de la barre latérale."))
        func noAccountInThisSession() -> Measurement {
            if localUserCount == 1 {
                return Measurement(id: id, value: .int(0), status: .good, method: method, collectedAt: now,
                                   display: L("No account signed in", "Aucun compte connecté"),
                                   detail: L("No Apple Account is signed in in this session.", "Aucun compte Apple n'est connecté dans cette session."),
                                   note: decisive)
            }
            return Measurement(id: id, value: .int(0), status: .manualRequired, method: method, collectedAt: now,
                               display: checkYourself,
                               detail: L("No Apple Account is signed in in this session.", "Aucun compte Apple n'est connecté dans cette session."),
                               note: L("This Mac has several user accounts. Only the current session was checked: sign in to each account, or erase the Mac, to be sure.",
                                       "Ce Mac a plusieurs comptes utilisateurs. Seule la session en cours a été vérifiée : ouvrez chaque compte, ou effacez le Mac, pour être sûr.") + " " + decisive)
        }
        if domainMissing {
            return noAccountInThisSession()
        }
        guard let data, let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return unreadable
        }
        // Plist lisible mais sans la clé attendue (ou d'un autre type) : on ne sait pas, donc pas vert.
        guard let accounts = root["Accounts"] as? [[String: Any]] else {
            return unreadable
        }
        if accounts.isEmpty {
            return noAccountInThisSession()
        }
        let findMy = accounts.contains { account in
            ((account["Services"] as? [[String: Any]]) ?? []).contains { service in
                (service["Name"] as? String) == "FIND_MY_MAC" && Self.flag(service["Enabled"])
            }
        }
        var detail = findMy
            ? L("An Apple Account is signed in and Find My Mac is on.", "Un compte Apple est connecté et Localiser mon Mac est activé.")
            : L("An Apple Account is signed in (Find My Mac off).", "Un compte Apple est connecté (Localiser mon Mac désactivé).")
        if findMy && activationLockOff && chip == .intelT2 {
            detail += " " + L("Activation Lock is still reported as off: on an Intel Mac with a T2 chip, it only arms with Secure Boot set to Full Security.",
                              "Le verrouillage d'activation est pourtant signalé désactivé : sur un Mac Intel à puce T2, il ne s'arme qu'avec le démarrage sécurisé en « Sécurité maximale ».")
        }
        return Measurement(id: id, value: .int(Int64(accounts.count)), status: .watch, method: method, collectedAt: now,
                           display: accounts.count > 1 ? L("\(accounts.count) accounts signed in", "\(accounts.count) comptes connectés")
                                                       : L("Account signed in", "Compte connecté"),
                           detail: detail,
                           note: L("To do before handing over the Mac: sign out (System Settings › Apple Account › Sign Out), then erase it. While signed in, the Mac can be located or locked remotely. ",
                                   "À faire avant la remise : se déconnecter (Réglages Système › Compte Apple › Se déconnecter), puis effacer le Mac. Tant qu'un compte est connecté, le Mac peut être localisé ou verrouillé à distance. ") + decisive)
    }

    /// Nombre de comptes utilisateurs locaux (UID ≥ 501) dans la sortie de `dscl . -list /Users UniqueID` ;
    /// nil si la sortie est absente ou vide.
    public static func localUserCount(dsclOutput output: String?) -> Int? {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var count = 0
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let uid = Int(parts.last!) else { continue }
            if uid >= 501 { count += 1 }
        }
        return count
    }

    private static func flag(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        return false
    }

    // MARK: MDM

    /// `profiles status -type enrollment`. Analyse tolérante : la sortie varie selon la version de macOS.
    public static func mdm(enrollmentOutput output: String?, exitCode: Int32?, now: Date = Date()) -> Measurement {
        let id = MetricID.mdm
        let method = "profiles status -type enrollment"
        guard let output, exitCode == 0 else {
            return Measurement(id: id, value: nil, status: .manualRequired, method: method, collectedAt: now,
                               display: checkYourself, note: mdmLimit)
        }
        func answer(_ prefix: String) -> Bool? {
            for line in output.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { continue }
                let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: ": ")).lowercased()
                if rest.hasPrefix("yes") { return true }
                if rest.hasPrefix("no") { return false }
            }
            return nil
        }
        let dep = answer("Enrolled via DEP")
        let enrolled = answer("MDM enrollment")
        // Valeur normalisée construite par le code : la sortie brute peut contenir l'adresse du serveur MDM.
        func yesNo(_ b: Bool?) -> String { b.map { $0 ? "yes" : "no" } ?? "unknown" }
        let normalized = "dep=\(yesNo(dep)); mdm=\(yesNo(enrolled))"
        if dep == true || enrolled == true {
            var parts: [String] = []
            if dep == true { parts.append(L("automated enrollment (Apple Business / School Manager)", "inscription automatique (Apple Business / School Manager)")) }
            if enrolled == true { parts.append(L("MDM enrollment", "inscription MDM")) }
            return Measurement(id: id, value: .text(normalized), status: .problem,
                               method: method, collectedAt: now, display: signalDetected,
                               detail: L("This Mac is managed by an organization: ", "Ce Mac est géré par une organisation : ") + parts.joined(separator: ", ") + ".",
                               note: L("Ask for proof that the organization has released the Mac.", "Demandez la preuve que l'organisation a libéré le Mac.") + " " + mdmLimit)
        }
        if dep == false && enrolled == false {
            // « Aucun signal » : `profiles` dit l'inscription actuelle, pas l'assignation du numéro de série
            // à une organisation. Une information neutre, pas un point fort.
            return Measurement(id: id, value: .text(normalized), status: .info,
                               method: method, collectedAt: now, display: noSignal,
                               detail: L("No company management in this session.", "Aucune gestion d'entreprise dans cette session."),
                               note: mdmLimit)
        }
        return Measurement(id: id, value: nil, status: .manualRequired, method: method, collectedAt: now,
                           display: checkYourself, note: mdmLimit)
    }

    // MARK: Mot de passe firmware

    /// Lecture impossible sans droits administrateur (Intel) ; sans objet sur puce Apple.
    public static func firmwarePassword(chip: ChipFamily?, now: Date = Date()) -> Measurement {
        let id = MetricID.firmwarePassword
        if chip == .appleSilicon {
            return Measurement(id: id, value: nil, status: .notApplicable, method: nil, collectedAt: now,
                               display: L("Not applicable", "Sans objet"),
                               detail: L("Apple silicon Macs have no firmware password.", "Les Mac à puce Apple n'ont pas de mot de passe firmware."),
                               note: L("Recovery lock goes through company management: see MDM.", "Le verrouillage de récupération passe par la gestion d'entreprise : voir MDM."))
        }
        return Measurement(id: id, value: nil, status: .manualRequired, method: "firmwarepasswd -check (droits administrateur requis)",
                           collectedAt: now, display: L("Check manually", "À vérifier soi-même"),
                           detail: L("Reading it requires administrator rights.", "Sa lecture exige les droits administrateur."),
                           note: L("Restart while holding Option (⌥): if a password is requested, the Mac is locked.",
                                   "Redémarrez en maintenant Option (⌥) : si un mot de passe est demandé, le Mac est verrouillé."))
    }

    // MARK: SIP, FileVault, machine virtuelle

    /// `csrutil status`. « enabled. » sur ce Mac ; « disabled » ou « Custom Configuration » : signe de bidouillage.
    public static func sip(csrutilOutput output: String?, now: Date = Date()) -> Measurement {
        let id = MetricID.sip
        let method = "csrutil status"
        guard let output, let line = output.split(whereSeparator: \.isNewline).first(where: { $0.contains("System Integrity Protection status") }) else {
            return .unavailable(id, note: L("macOS did not report the status.", "macOS n'a pas indiqué l'état."), method: method)
        }
        let lower = line.lowercased()
        if lower.contains("custom configuration") || lower.contains("unknown") {
            return Measurement(id: id, value: .text("custom"), status: .watch, method: method, collectedAt: now,
                               display: L("Partly disabled", "Partiellement désactivée"),
                               note: L("A sign that the system has been modified.", "Signe que le système a été modifié."))
        }
        if lower.contains("disabled") {
            return Measurement(id: id, value: .text("disabled"), status: .watch, method: method, collectedAt: now,
                               display: L("Disabled", "Désactivée"),
                               note: L("A sign that the system has been modified.", "Signe que le système a été modifié."))
        }
        if lower.contains("enabled") {
            return Measurement(id: id, value: .text("enabled"), status: .good, method: method, collectedAt: now,
                               display: L("Enabled", "Activée"))
        }
        return .unavailable(id, note: L("Unexpected answer from macOS.", "Réponse inattendue de macOS."), method: method)
    }

    /// `fdesetup status` : « FileVault is On. » / « FileVault is Off. ». Information, sans jugement.
    public static func fileVault(fdesetupOutput output: String?, now: Date = Date()) -> Measurement {
        let id = MetricID.fileVault
        let method = "fdesetup status"
        let lower = output?.lowercased() ?? ""
        if lower.contains("filevault is on") {
            return Measurement(id: id, value: .bool(true), status: .info, method: method, collectedAt: now,
                               display: L("On", "Activé"))
        }
        if lower.contains("filevault is off") {
            return Measurement(id: id, value: .bool(false), status: .info, method: method, collectedAt: now,
                               display: L("Off", "Désactivé"))
        }
        return .unavailable(id, note: L("macOS did not report the status.", "macOS n'a pas indiqué l'état."), method: method)
    }

    /// `sysctl kern.hv_vmm_present` : 1 dans une machine virtuelle.
    public static func virtualMachine(hvVmmPresent: Int?, now: Date = Date()) -> Measurement {
        let id = MetricID.virtualMachine
        let method = "sysctl kern.hv_vmm_present"
        guard let value = hvVmmPresent else {
            return .unavailable(id, note: L("Could not be read.", "Lecture impossible."), method: method)
        }
        if value != 0 {
            return Measurement(id: id, value: .int(Int64(value)), status: .problem, method: method, collectedAt: now,
                               display: L("Report generated in a virtual machine", "Rapport généré dans une machine virtuelle"),
                               note: L("The values in this report do not describe a real Mac.", "Les valeurs de ce rapport ne décrivent pas un vrai Mac."))
        }
        return Measurement(id: id, value: .int(0), status: .good, method: method, collectedAt: now,
                           display: L("No", "Non"))
    }

    /// `profiles list` sans droits administrateur : seuls les profils de l'utilisateur sont visibles.
    public static func configurationProfiles(listOutput output: String?, now: Date = Date()) -> Measurement {
        let id = MetricID.configProfiles
        let method = "profiles list"
        let limit = L("System-wide profiles can only be listed with administrator rights.",
                      "Les profils installés pour tout le système ne sont visibles qu'avec les droits administrateur.")
        guard let output else { return .unavailable(id, note: limit, method: method) }
        if output.lowercased().contains("there are no configuration profiles installed") {
            return Measurement(id: id, value: .int(0), status: .info, method: method, collectedAt: now,
                               display: L("None for this user", "Aucun pour cet utilisateur"), note: limit)
        }
        let count = output.split(whereSeparator: \.isNewline).filter { $0.contains("profileIdentifier") }.count
        if count > 0 {
            return Measurement(id: id, value: .int(Int64(count)), status: .info, method: method, collectedAt: now,
                               display: L("\(count) installed", "\(count) installé(s)"), note: limit)
        }
        return .unavailable(id, note: limit, method: method)
    }
}
