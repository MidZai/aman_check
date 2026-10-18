import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

@Suite("Mesures et catalogue")
struct MeasurementTests {
    @Test("Une donnée absente n'est jamais verte, orange, rouge ni « information »")
    func nilValueNeverJudged() {
        for status in [CheckStatus.good, .watch, .problem, .info] {
            #expect(Measurement(id: MetricID.batteryHealth, value: nil, status: status).status == .unavailable)
        }
        #expect(Measurement(id: MetricID.batteryHealth, value: nil, status: .manualRequired).status == .manualRequired)
        #expect(Measurement(id: MetricID.batteryHealth, value: .int(80), status: .good).status == .good)
    }

    @Test("Chaque identifiant a un libellé humain, sans snake_case")
    func catalogLabels() {
        let ids = [MetricID.activationLock, MetricID.appleAccount, MetricID.mdm, MetricID.firmwarePassword, MetricID.sip, MetricID.fileVault,
                   MetricID.virtualMachine, MetricID.configProfiles, MetricID.securityChip, MetricID.modelName,
                   MetricID.modelIdentifier, MetricID.modelYear, MetricID.chip, MetricID.cpuCores, MetricID.gpu,
                   MetricID.ram, MetricID.storageCapacity, MetricID.macOS, MetricID.macOSMax, MetricID.serial,
                   MetricID.display, MetricID.batteryHealth, MetricID.batteryCycles, MetricID.batteryCondition,
                   MetricID.batteryDesignCapacity, MetricID.batteryMaxCapacity, MetricID.batteryCharging,
                   MetricID.batteryTemperature, MetricID.storageHealth, MetricID.storagePowerOnHours,
                   MetricID.storageDataWritten, MetricID.storagePercentageUsed, MetricID.storageAvailableSpare,
                   MetricID.storageMediaErrors, MetricID.storageTemperature, MetricID.storageModel,
                   MetricID.storageInterface, MetricID.wifi, MetricID.bluetooth,
                   MetricID.batteryPresence, MetricID.cameraPresence, MetricID.touchIDPresence,
                   MetricID.fanCount, MetricID.fanSpeed, MetricID.cpuTemperature, MetricID.ambientLight]
        #expect(Set(ids).count == MetricCatalog.allIDs.count)
        for id in ids {
            #expect(MetricCatalog.contains(id), "\(id) sans libellé")
            let label = MetricCatalog.info(for: id).label
            #expect(!label.contains("_"), "\(id) : \(label)")
            #expect(label != id)
        }
    }

    @Test("Informations sans jugement : aucune pastille sur modèle, processeur, RAM, macOS, n° de série")
    func noJudgementOnIdentity() {
        for id in [MetricID.modelName, MetricID.chip, MetricID.ram, MetricID.macOS, MetricID.serial, MetricID.cpuCores] {
            #expect(MetricCatalog.info(for: id).isJudged == false)
        }
    }

    @Test("Heures du SSD : jamais présentées comme des heures du Mac ; « TBW » absent")
    func lexiconStorage() {
        let hours = MetricCatalog.info(for: MetricID.storagePowerOnHours).label.lowercased()
        #expect(hours.contains("ssd"))
        for id in MetricCatalog.allIDs {
            let info = MetricCatalog.info(for: id)
            let text = (info.label + " " + (info.help ?? "")).lowercased()
            for word in ["certifi", "garanti", "infalsifiable", "100 % fonctionnel", "grade a", "tbw", "warrant"] {
                #expect(!text.contains(word), "\(id) contient « \(word) »")
            }
        }
    }
}

@Suite("Profil de machine")
struct DeviceProfileTests {
    @Test("MacBookPro16,1 : portable Touch Bar, Échap physique, 4 ports, dernier macOS 26")
    func mbp16() {
        let p = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        #expect(p.isRecognized)
        #expect(p.kind == .laptop)
        #expect(p.hasTouchBar)
        #expect(p.hasPhysicalEscape)
        #expect(!p.hasPhysicalFunctionRow)
        #expect(p.thunderboltPorts == 4)
        #expect(p.model?.lastMacOS == 26)
        #expect(p.chip == .intelT2)
        #expect(Set(TestID.applicable(to: p)) == Set(TestID.allCases))
    }

    @Test("Mac mini simulé : ni clavier, ni trackpad, ni caméra, ni micro, ni Touch ID, ni batterie")
    func macMini() {
        let p = DeviceProfile.make(modelIdentifier: "Macmini9,1", detected: .init(hasBattery: true, hasBuiltInCamera: true), simulated: true)
        #expect(p.kind == .mini)
        #expect(!p.hasBattery) // en simulation, les détections de la vraie machine sont ignorées
        let tests = TestID.applicable(to: p)
        #expect(!tests.contains(.keyboard))
        #expect(!tests.contains(.trackpad))
        #expect(!tests.contains(.camera))
        #expect(!tests.contains(.microphone))
        #expect(!tests.contains(.touchID))
        #expect(!tests.contains(.touchBar))
        #expect(!tests.contains(.screen)) // pas d'écran intégré : le test d'écran n'est pas planifié (B4.4)
        #expect(tests.contains(.speakers))
        #expect(p.thunderboltPorts == nil) // pas de total affiché
    }

    @Test("Profils de simulation demandés")
    func simulationTargets() {
        #expect(DeviceProfile.make(modelIdentifier: "iMac21,1", simulated: true).hasBuiltInCamera)
        #expect(!DeviceProfile.make(modelIdentifier: "Mac13,1", simulated: true).hasBuiltInCamera)
        let air = DeviceProfile.make(modelIdentifier: "MacBookAir10,1", simulated: true)
        #expect(air.hasPhysicalFunctionRow && !air.hasTouchBar && air.chip == .appleSilicon)
        #expect(!TestID.applicable(to: air).contains(.touchBar))
        let mbp14 = DeviceProfile.make(modelIdentifier: "MacBookPro18,3", simulated: true)
        #expect(mbp14.hasSDSlot && mbp14.hasHDMI && mbp14.hasMagSafe && mbp14.thunderboltPorts == 3)
    }

    @Test("Modèle inconnu : profil générique prudent")
    func unknownModel() {
        let p = DeviceProfile.make(modelIdentifier: "Mac99,9", detected: .init(hasBattery: true))
        #expect(!p.isRecognized)
        #expect(p.kind == .laptop)
        #expect(p.displayName == "Mac99,9")
        #expect(p.thunderboltPorts == nil)
        #expect(DeviceProfile.make(modelIdentifier: "Mac99,9", detected: .init(hasBattery: false)).kind == .unknown)
    }

    @Test("Argument --simulate-model")
    func simulateArgument() {
        #expect(DeviceProfile.simulatedIdentifier(arguments: ["app", "--simulate-model", "Macmini9,1"]) == "Macmini9,1")
        #expect(DeviceProfile.simulatedIdentifier(arguments: ["app", "--simulate-model"]) == nil)
        #expect(DeviceProfile.simulatedIdentifier(arguments: ["app"]) == nil)
    }

    @Test("Catalogue : aucun identifiant en double, nom commercial lisible")
    func catalog() {
        let ids = MacModelCatalog.all.flatMap(\.identifiers)
        #expect(ids.count == Set(ids).count)
        let name = MacModelCatalog.model(for: "MacBookPro16,1")?.displayName ?? ""
        #expect(name.hasPrefix("MacBook Pro ("))
        #expect(name.contains("16"))
        #expect(name.contains("2019"))
    }
}

@Suite("Disposition du clavier")
struct KeyboardLayoutTests {
    @Test("Totaux tirés du modèle (MBP 16″ 2019 : Touch Bar)", arguments: [
        (PhysicalKeyboard.ansi, KeyboardTopRow.touchBar, 65),
        (.iso, .touchBar, 66),
        (.ansi, .functionKeys, 77),
        (.iso, .functionKeys, 78)
    ])
    func counts(physical: PhysicalKeyboard, top: KeyboardTopRow, expected: Int) {
        let layout = KeyboardLayout.macBook(physical: physical, topRow: top)
        #expect(layout.keyCount == expected)
        let codes = layout.keys.map(\.code)
        #expect(codes.count == Set(codes).count, "keyCode en double")
    }

    @Test("Rangée du bas complète : fn, ⌃, ⌥ et ⌘ des deux côtés, espace, flèches")
    func bottomRow() {
        let layout = KeyboardLayout.macBook(physical: .iso, topRow: .touchBar)
        for code: UInt16 in [63, 59, 58, 55, 49, 54, 61, 123, 124, 125, 126, 56, 60, 57, 53] {
            #expect(layout.key(forCode: code) != nil, "keyCode \(code) absent")
        }
    }

    @Test("ISO : kVK_ISO_Section (10) et touche à côté de Maj (50) ; ANSI : pas de 10")
    func isoVsAnsi() {
        let iso = KeyboardLayout.macBook(physical: .iso, topRow: .touchBar)
        #expect(iso.key(forCode: 10) != nil)
        #expect(iso.key(forCode: 50) != nil)
        let ansi = KeyboardLayout.macBook(physical: .ansi, topRow: .touchBar)
        #expect(ansi.key(forCode: 10) == nil)
        #expect(ansi.key(forCode: 50) != nil)
    }

    @Test("Rangée F1–F12 : touches média acceptées sans fn")
    func mediaKeys() {
        let layout = KeyboardLayout.macBook(physical: .ansi, topRow: .functionKeys)
        #expect(layout.key(forMediaKeyType: 0)?.code == 111) // volume + → F12
        #expect(layout.key(forMediaKeyType: 3)?.code == 122) // luminosité − → F1
    }

    @Test("Toutes les rangées tiennent dans la largeur du clavier")
    func geometry() {
        for physical in PhysicalKeyboard.allCases {
            for top in [KeyboardTopRow.touchBar, .functionKeys] {
                let layout = KeyboardLayout.macBook(physical: physical, topRow: top)
                for key in layout.keys {
                    #expect(key.x + key.w <= layout.width + 0.001, "\(key.label) déborde")
                }
            }
        }
    }
}

@Suite("Rapport")
struct ReportTests {
    private func report(measurements: [Measurement], tests: [TestResult] = []) -> ConditionReport {
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        return ConditionReport(appVersion: "test", profile: profile, measurements: measurements, tests: tests,
                               plannedTests: TestID.applicable(to: profile))
    }

    @Test("Compteurs : tests non faits comptés « non testés », blocage remonté")
    func summary() {
        let r = report(measurements: [
            Measurement(id: MetricID.activationLock, value: .text("activation_lock_enabled"), status: .problem),
            Measurement(id: MetricID.mdm, value: .text("no"), status: .good),
            SecurityAnalysis.firmwarePassword(chip: .intelT2),
            Measurement(id: MetricID.ram, value: .int(32), status: .info),
            Measurement(id: MetricID.batteryHealth, value: .int(75), status: .watch)
        ], tests: [
            TestResult(test: .screen, outcome: .passed, provenance: .userObserved, summary: "ok"),
            TestResult.notTested(.camera, reason: "refus")
        ])
        let s = ReportSummary(report: r)
        #expect(s.good == 2)        // MDM + écran
        #expect(s.watch == 1)
        #expect(s.problem == 1)
        #expect(s.toCheck == 1)     // mot de passe firmware
        #expect(s.notTested == 11)  // 12 tests prévus (Touch Bar et 3 capteurs compris), 1 réussi
        #expect(s.testsDone == 1)
        #expect(s.testsPlanned == 12)
        #expect(s.blockers.map(\.id) == [MetricID.activationLock])
    }

    @Test("Test ignoré ou interrompu = « Non testé », jamais « Échoué »")
    func skippedIsNotFailed() {
        #expect(TestResult.notTested(.camera, reason: "x").status == .notTested)
        #expect(TestResult.notTested(.camera, reason: "x", aborted: true).status == .notTested)
        #expect(TestResult(test: .camera, outcome: .failed, provenance: .userObserved, summary: "x").status == .problem)
    }

    @Test("« À vérifier » : problèmes d'abord, puis vérifications manuelles et tests manquants")
    func toCheck() {
        let r = report(measurements: [
            SecurityAnalysis.firmwarePassword(chip: .intelT2),
            Measurement(id: MetricID.mdm, value: .text("yes"), status: .problem),
            Measurement(id: MetricID.storageTemperature, value: nil, status: .unavailable)
        ])
        let points = ReportInsights.toCheck(r)
        #expect(points.first?.key == MetricID.mdm)
        #expect(points.contains { $0.key == MetricID.firmwarePassword })
        #expect(!points.contains { $0.key == MetricID.storageTemperature }) // détail avancé non disponible : pas d'alerte
        // Les 8 tests non réalisés tiennent sur une seule ligne.
        #expect(points.filter { $0.key.hasPrefix("test.") }.isEmpty)
        #expect(points.last?.key == "tests.notTested")
    }

    @Test("Points forts : seulement à partir de mesures faites et jugées bonnes")
    func strengths() {
        let empty = ReportInsights.strengths(report(measurements: []))
        #expect(empty.allSatisfy { $0.key == "macos" })
        let r = report(measurements: [
            Measurement(id: MetricID.activationLock, value: .text("d"), status: .good),
            Measurement(id: MetricID.mdm, value: .text("n"), status: .info),
            Measurement(id: MetricID.batteryHealth, value: .int(83), status: .good),
            Measurement(id: MetricID.batteryCycles, value: .int(510), status: .good)
        ])
        let strengths = ReportInsights.strengths(r)
        let keys = strengths.map(\.key)
        #expect(keys.contains("locks"))
        #expect(keys.contains("battery"))
        // Le point fort ne dépend que du verrouillage d'activation et ne parle plus de gestion d'entreprise.
        let locks = strengths.first { $0.key == "locks" }
        #expect(locks?.title == L("No Activation Lock detected", "Aucun verrouillage d'activation détecté"))
        #expect(strengths.allSatisfy { !$0.title.lowercased().contains("company management") })
        let withoutMDM = report(measurements: [Measurement(id: MetricID.activationLock, value: .text("d"), status: .good)])
        #expect(ReportInsights.strengths(withoutMDM).contains { $0.key == "locks" })
    }

    @Test("Identifiant de rapport : format AC-XXXX-XXXX, non répété")
    func reportID() {
        let a = ConditionReport.makeID()
        #expect(a.count == 12)
        #expect(a.hasPrefix("AC-"))
        #expect(a != ConditionReport.makeID())
    }

    @Test("Le rapport s'encode et se relit en JSON")
    func codable() throws {
        let r = report(measurements: [Measurement(id: MetricID.batteryHealth, value: .int(83), status: .good)],
                       tests: [TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "65/65")])
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(ConditionReport.self, from: data)
        #expect(back.measurements.first?.value == .int(83))
        #expect(back.tests.first?.test == .keyboard)
        #expect(back.trustLevel == 1)
    }
}

@Suite("Composant attendu mais non détecté")
struct MissingComponentTests {
    private func missing(_ detected: DeviceProfile.Detected, model: String = "MacBookPro16,1") -> [Measurement] {
        DeviceProfile.make(modelIdentifier: model, detected: detected).missingComponentMeasurements()
    }

    @Test("Touch ID attendu par le catalogue mais absent : ligne problème, test guidé non proposé")
    func touchIDMissing() {
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true, hasBuiltInCamera: true, hasBiometrics: false))
        #expect(profile.hasTouchID, "the component stays in the profile")
        let lines = profile.missingComponentMeasurements()
        #expect(lines.map(\.id) == [MetricID.touchIDPresence])
        #expect(lines.first?.status == .problem)
        #expect(lines.first?.displayText == L("Expected on this model but not detected.", "Attendu sur ce modèle mais non détecté."))
        #expect(lines.first?.note == L("The part may be disconnected, faulty or replaced by a non-genuine one.", "La pièce peut être débranchée, défectueuse ou remplacée par une pièce non d'origine."))
        #expect(!TestID.applicable(to: profile).contains(.touchID))
        #expect(MetricCatalog.contains(MetricID.touchIDPresence))
    }

    @Test("Caméra et batterie : même règle")
    func cameraAndBatteryMissing() {
        #expect(missing(.init(hasBattery: true, hasBuiltInCamera: false, hasBiometrics: true)).map(\.id) == [MetricID.cameraPresence])
        let camera = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true, hasBuiltInCamera: false, hasBiometrics: true))
        #expect(!TestID.applicable(to: camera).contains(.camera))
        #expect(missing(.init(hasBattery: false, hasBuiltInCamera: true, hasBiometrics: true)).map(\.id) == [MetricID.batteryPresence])
        #expect(missing(.init(hasBattery: true, hasBuiltInCamera: true, hasBiometrics: true)).isEmpty)
    }

    @Test("Modèle inconnu : la détection fait foi, aucune ligne")
    func unknownModelKeepsDetection() {
        let profile = DeviceProfile.make(modelIdentifier: "Mac99,9", detected: .init(hasBattery: true, hasBuiltInCamera: false, hasBiometrics: false))
        #expect(profile.missingComponentMeasurements().isEmpty)
        #expect(!profile.hasTouchID)
    }

    @Test("Le résumé compte le composant manquant comme problème, pas comme non testé")
    func summaryCountsProblem() {
        let profile = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true, hasBuiltInCamera: true, hasBiometrics: false))
        let report = ConditionReport(appVersion: "test", profile: profile, measurements: profile.missingComponentMeasurements(),
                                     tests: [], plannedTests: TestID.applicable(to: profile))
        let summary = ReportSummary(report: report)
        #expect(summary.problem == 1)
        #expect(summary.notTested == 11)
    }
}

@Suite("Numéro de série · 4 derniers caractères")
struct SerialNumberTextTests {
    @Test("Série à 12 caractères : note de configuration partagée ; série récente : aucune note")
    func configurationNote() {
        let note = SerialNumberText.configurationNote(serialLength: 12)
        #expect(note == L("On this generation of Mac, these 4 characters are shared by every Mac of the same configuration. They don't identify this exact Mac: compare the full serial number.",
                          "Sur cette génération de Mac, ces 4 caractères sont communs à tous les Mac de même configuration. Ils n'identifient pas cet exemplaire : comparez le numéro de série complet."))
        #expect(SerialNumberText.configurationNote(serialLength: 10) == nil)
        #expect(SerialNumberText.configurationNote(serialLength: 11) == nil)
    }

    @Test("Les textes du niveau 2 ne présentent plus les 4 caractères comme une identification")
    func level2TextsAreHonest() {
        for text in [Level2Text.checkThisMac, Level2Text.buyerChecks[0]] {
            #expect(!text.lowercased().contains(L("identif", "reconna")), Comment(rawValue: text))
        }
        #expect(Level2Text.checkThisMac.contains(L("rule out", "écarter")))
    }
}

@Suite("Niveau 2 · ce que la page prouve")
struct Level2ProvesTests {
    @Test("Le rapport publié ne promet pas plus que ce que le serveur vérifie")
    func provesIsHonest() {
        #expect(Level2Text.proves.first == L("It was published by the holder of a license key, on the date shown, and has not been changed since.",
                                             "Il a été publié par le titulaire d'une clé de licence, à la date indiquée, et n'a pas été modifié depuis."))
        #expect(!Level2Text.proves.contains { $0.contains(L("produced by the Aman Check app", "produit par l'app Aman Check")) })
    }
}

@Suite("Tests audio · provenance")
struct AudioDeviceTextTests {
    @Test("Seule la catégorie du périphérique est enregistrée, jamais son nom")
    func categoryOnly() {
        #expect(AudioDeviceText.category(isBuiltIn: true, input: true) == L("Built-in microphone", "Micro intégré"))
        #expect(AudioDeviceText.category(isBuiltIn: false, input: true) == L("External microphone", "Micro externe"))
        #expect(AudioDeviceText.category(isBuiltIn: true, input: false) == L("Built-in speakers", "Haut-parleurs intégrés"))
        #expect(AudioDeviceText.category(isBuiltIn: false, input: false) == L("External output", "Sortie externe"))
        #expect(AudioDeviceText.externalDeviceReason == L("An external audio device was in use: disconnect it and run the test again.",
                                                           "Un périphérique audio externe était utilisé : débranchez-le et relancez le test."))
    }
}

@Suite("Ports · comptage")
struct PortsTallyTests {
    @Test("Seuls les connecteurs du Mac (numéro de port USB-C) remplissent une case ; un hub n'en remplit aucune")
    func numberedPortsOnly() {
        #expect(PortsTally.filledSlots(portNumbers: [1, nil, 3, 3, 9], total: 4) == [1, 3])
        #expect(PortsTally.hubHint == L("Plug the device directly into the Mac, without a hub.", "Branchez l'appareil directement sur le Mac, sans concentrateur."))
    }

    @Test("Réussi seulement si tous les ports attendus ont été vus ; partiel sans port mort = à surveiller")
    func verdict() {
        #expect(PortsTally.verdict(portNumbers: [1, 2, 3, 4], total: 4, anyDead: false) == .complete)
        #expect(PortsTally.verdict(portNumbers: [1, 2], total: 4, anyDead: false) == .partial(seen: 2, total: 4))
        #expect(PortsTally.verdict(portNumbers: [1, nil, nil], total: 2, anyDead: false) == .partial(seen: 1, total: 2))
        #expect(PortsTally.verdict(portNumbers: [1, 2], total: 4, anyDead: true) == .failed)
        #expect(PortsTally.verdict(portNumbers: [], total: 4, anyDead: false) == .none)
        #expect(PortsTally.partialText(seen: 2, total: 4) == L("2 of 4 ports tested.", "2 ports testés sur 4."))
    }
}

@Suite("Clavier · JIS et Échap")
struct KeyboardLayoutRulesTests {
    @Test("La disposition JIS contient ¥, _, 英数 et かな")
    func jisKeys() {
        let layout = KeyboardLayout.macBook(physical: .jis, topRow: .functionKeys)
        let labels = Set(layout.keys.map(\.label))
        #expect(labels.isSuperset(of: ["¥", "_", "英数", "かな"]))
        #expect(PhysicalKeyboard.allCases.map(\.label) == ["ANSI", "ISO", "JIS"])
        #expect(layout.physical == .jis)
    }

    @Test("Touch Bar sans Échap physique : la touche esc n'est pas attendue")
    func noPhysicalEscape() {
        let withEsc = KeyboardLayout.macBook(physical: .ansi, topRow: .touchBar, hasPhysicalEscape: true)
        let without = KeyboardLayout.macBook(physical: .ansi, topRow: .touchBar, hasPhysicalEscape: false)
        #expect(withEsc.keys.contains { $0.code == 53 })
        #expect(!without.keys.contains { $0.code == 53 })
        #expect(without.keyCount == withEsc.keyCount - 1)
    }
}

@Suite("Écran intégré")
struct BuiltInDisplayTests {
    @Test("Le test d'écran n'est planifié que sur un Mac à écran intégré")
    func screenTestOnlyWithBuiltInDisplay() {
        let laptop = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        let mini = DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
        let imac = DeviceProfile.make(modelIdentifier: "iMac21,1", simulated: true)
        #expect(laptop.hasBuiltInDisplay && imac.hasBuiltInDisplay && !mini.hasBuiltInDisplay)
        #expect(TestID.applicable(to: laptop).contains(.screen))
        #expect(!TestID.applicable(to: mini).contains(.screen))
    }
}

@Suite("Analyse · tests guidés déjà faits")
struct AnalysisStartTests {
    @Test("Les tests faits avant la première analyse sont rattachés à cette analyse")
    func existingResultsAreKept() {
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let now = earlier.addingTimeInterval(600)
        let done = TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "ok", completedAt: earlier)
        #expect(TestResult.analysisStart(keeping: [done], now: now) == earlier)
        #expect(TestResult.analysisStart(keeping: [], now: now) == now)
        #expect(TestResult.belonging(toAnalysisStartedAt: TestResult.analysisStart(keeping: [done], now: now), [done]).count == 1)
    }
}

@Suite("Point fort macOS")
struct LatestMacOSTests {
    private func report() -> ConditionReport {
        // Mac Apple silicon : encore pris en charge par la dernière version (un Mac Intel s'arrête à macOS 26).
        let profile = DeviceProfile.make(modelIdentifier: "Mac14,2", detected: .init(hasBattery: true))
        return ConditionReport(appVersion: "test", profile: profile, measurements: [], tests: [], plannedTests: [])
    }

    @Test("Une version de macOS plus récente que celle connue devient la référence")
    func runningMajorBeyondKnown() {
        #expect(MacOSRelease.reference(runningMajor: 27) == 27)
        #expect(MacOSRelease.reference(runningMajor: 15) == MacOSRelease.latestKnown)
    }

    @Test("Le point fort n'existe que si l'app a moins de 18 mois ; au-delà, texte neutre")
    func strengthAgesOut() {
        let built = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = ReportInsights.strengths(report(), builtAt: built, now: built.addingTimeInterval(30 * 86_400))
        #expect(fresh.first { $0.key == "macos" }?.title.contains(L("Runs", "Reçoit")) == true || fresh.first { $0.key == "macos" }?.title.contains(L("latest", "dernier")) == true)
        let stale = ReportInsights.strengths(report(), builtAt: built, now: built.addingTimeInterval(19 * 30 * 86_400))
        #expect(stale.first { $0.key == "macos" }?.title == L("Ran \(MacOSRelease.name(MacOSRelease.latestKnown)) when this version of Aman Check was released.",
                                                              "Faisait tourner \(MacOSRelease.name(MacOSRelease.latestKnown)) à la sortie de cette version d'Aman Check."))
        #expect(stale.first { $0.key == "macos" }?.status == .info)
        #expect(ReportInsights.strengths(report(), builtAt: nil, now: built).first { $0.key == "macos" }?.status == .info)
    }
}

@Suite("Accessoires des Mac de bureau")
struct AccessoryTestsTests {
    @Test("Clavier et trackpad facultatifs sur un iMac, absents d'un portable")
    func accessoriesOnlyOnDesktops() {
        let imac = DeviceProfile.make(modelIdentifier: "iMac21,1", simulated: true)
        let laptop = DeviceProfile.make(modelIdentifier: "MacBookPro16,1", detected: .init(hasBattery: true))
        #expect(TestID.accessories(for: imac) == [.keyboard, .trackpad])
        #expect(TestID.accessories(for: laptop).isEmpty)
        // Jamais prévus : ni dans l'assistant, ni comptés « non testés ».
        #expect(!TestID.applicable(to: imac).contains(.keyboard))
        #expect(!TestID.applicable(to: imac).contains(.trackpad))
    }

    @Test("Un accessoire testé entre dans le rapport ; ignoré, il n'y apparaît pas")
    func reportedOnlyWhenDone() {
        let imac = DeviceProfile.make(modelIdentifier: "iMac21,1", simulated: true)
        let planned = TestID.applicable(to: imac)
        #expect(TestID.reported(for: imac, results: []) == planned)

        let keyboard = TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: "65 / 65")
        let trackpad = TestResult.notTested(.trackpad, reason: "ignoré")
        let reported = TestID.reported(for: imac, results: [keyboard, trackpad])
        #expect(reported.contains(.keyboard))
        #expect(!reported.contains(.trackpad))
        #expect(reported.filter { $0 != .keyboard } == planned)

        let report = ConditionReport(reportID: "T", generatedAt: Date(), appVersion: "1", profile: imac, measurements: [],
                                     tests: [keyboard], plannedTests: reported)
        let summary = ReportSummary(report: report)
        #expect(summary.testsPlanned == planned.count + 1)
        #expect(summary.testsDone == 1)
    }

    @Test("Un trackpad défaillant reste dans le rapport")
    func failedAccessoryIsReported() {
        let mini = DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
        let failed = TestResult(test: .trackpad, outcome: .failed, status: .watch, provenance: .measuredAuto, summary: "3 / 5")
        #expect(TestID.reported(for: mini, results: [failed]).contains(.trackpad))
    }
}
