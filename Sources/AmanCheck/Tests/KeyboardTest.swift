import SwiftUI
import AppKit
import Carbon
import IOKit.hid
import AmanCore
import AmanDesign
import DiskHealthCore

/// Détection du clavier physique et des étiquettes de la disposition active.
enum KeyboardInfo {
    /// Type physique via `KBGetLayoutType(LMGetKbdType())` (Carbon, déprécié mais fonctionnel).
    /// Ce n'est pas la source de saisie (« Français ») : c'est la forme du clavier (ISO / ANSI / JIS).
    static func physicalType() -> (PhysicalKeyboard, isJIS: Bool) {
        let type = KBGetLayoutType(Int16(LMGetKbdType()))
        DiagnosticLog.shared.log("clavier", "LMGetKbdType=\(LMGetKbdType()) KBGetLayoutType=\(type)")
        switch type {
        case OSType(kKeyboardISO): return (.iso, false)
        case OSType(kKeyboardJIS): return (.jis, true)
        default: return (.ansi, false)
        }
    }

    /// Caractère produit par un keyCode dans la disposition active (AZERTY, QWERTZ, arabe…).
    static func characterLabels(for codes: [UInt16]) -> [UInt16: String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        var labels: [UInt16: String] = [:]
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in codes {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
                if status == noErr, length > 0 {
                    let text = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                        labels[code] = text.uppercased()
                    }
                }
            }
        }
        return labels
    }
}

/// Réception des événements clavier par moniteur local (pas d'autorisation « Surveillance de l'entrée » :
/// l'app doit avoir le focus). Tous les événements sont consommés pendant le test.
@MainActor
final class KeyboardTestModel: ObservableObject {
    @Published var physical: PhysicalKeyboard
    @Published var topRow: KeyboardTopRow
    @Published private(set) var detected: Set<UInt16> = []
    @Published private(set) var held: Set<UInt16> = []
    @Published private(set) var lastKey: String?
    @Published private(set) var labels: [UInt16: String] = [:]
    let detectedPhysical: PhysicalKeyboard
    let isJIS: Bool
    /// Touch Bar sans touche Échap physique (2016–2017) : esc n'est pas attendue.
    let hasPhysicalEscape: Bool
    private var monitor: Any?

    init(profile: DeviceProfile) {
        let (type, jis) = KeyboardInfo.physicalType()
        detectedPhysical = type
        isJIS = jis
        physical = type
        topRow = profile.hasTouchBar ? .touchBar : .functionKeys
        hasPhysicalEscape = profile.hasPhysicalEscape
        refreshLabels()
    }

    var layout: KeyboardLayout { KeyboardLayout.macBook(physical: physical, topRow: topRow, hasPhysicalEscape: hasPhysicalEscape) }

    var missingKeys: [KeyboardKey] { layout.keys.filter { !detected.contains($0.code) } }

    func label(for key: KeyboardKey) -> String {
        key.isCharacter ? (labels[key.code] ?? key.label) : key.label
    }

    func refreshLabels() {
        labels = KeyboardInfo.characterLabels(for: KeyboardLayout.macBook(physical: .iso, topRow: .functionKeys).keys.filter(\.isCharacter).map(\.code))
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        DiagnosticLog.shared.log("clavier", "moniteur installé · disposition \(physical.rawValue) / \(topRow.rawValue) · \(layout.keyCount) touches")
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func reset() {
        detected = []
        held = []
        lastKey = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            DiagnosticLog.shared.log("clavier", "keyDown keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue) repeat=\(event.isARepeat)")
            // Seule une touche ISO envoie kVK_ISO_Section : le clavier est forcément ISO.
            if event.keyCode == UInt16(kVK_ISO_Section), physical == .ansi { physical = .iso }
            mark(event.keyCode)
            held.insert(event.keyCode)
            return nil
        case .keyUp:
            held.remove(event.keyCode)
            return nil
        case .flagsChanged:
            DiagnosticLog.shared.log("clavier", "flagsChanged keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)")
            let code = event.keyCode
            if isModifierDown(code: code, flags: event.modifierFlags) {
                mark(code)
                held.insert(code)
            } else {
                held.remove(code)
            }
            return nil
        case .systemDefined:
            // Touches média de la rangée du haut (sans fn) : sous-type 8, data1 = type << 16 | état.
            guard event.subtype.rawValue == 8 else { return event }
            let type = (event.data1 & 0xFFFF0000) >> 16
            let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA
            DiagnosticLog.shared.log("clavier", "systemDefined NX_KEYTYPE=\(type) down=\(isDown)")
            if isDown, let key = layout.key(forMediaKeyType: type) { mark(key.code) }
            return event // le système doit continuer à régler le son / la luminosité
        default:
            return event
        }
    }

    private func mark(_ code: UInt16) {
        guard let key = layout.key(forCode: code) else {
            DiagnosticLog.shared.log("clavier", "keyCode \(code) hors disposition")
            return
        }
        detected.insert(key.code)
        lastKey = label(for: key).isEmpty ? L("space", "espace") : label(for: key)
    }

    /// Une touche de modificateur est enfoncée si son drapeau est présent (Verr. Maj : à chaque bascule).
    private func isModifierDown(code: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch Int(code) {
        case kVK_Shift, kVK_RightShift: return flags.contains(.shift)
        case kVK_Control, kVK_RightControl: return flags.contains(.control)
        case kVK_Option, kVK_RightOption: return flags.contains(.option)
        case kVK_Command, kVK_RightCommand: return flags.contains(.command)
        case kVK_Function: return flags.contains(.function)
        case kVK_CapsLock: return true
        default: return false
        }
    }
}

struct KeyboardTestView: View {
    let profile: DeviceProfile
    let finish: (TestResult) -> Void
    @StateObject private var model: KeyboardTestModel
    @StateObject private var gate = ExternalInputMonitor(test: .keyboard)
    @State private var showMissing = false

    init(profile: DeviceProfile, finish: @escaping (TestResult) -> Void) {
        self.profile = profile
        self.finish = finish
        _model = StateObject(wrappedValue: KeyboardTestModel(profile: profile))
    }

    var body: some View {
        // Un clavier externe pourrait valider le test à la place de celui du Mac : le test ne démarre pas.
        Group {
            if gate.isBlocked {
                ExternalInputBlockedView(test: .keyboard, blockers: gate.blockers, finish: finish)
            } else {
                testBody
            }
        }
        .onAppear {
            gate.start()
            if !gate.isBlocked { model.start() }
        }
        .onDisappear {
            gate.stop()
            model.stop()
        }
        .onChange(of: gate.isBlocked) { _, blocked in
            // Clavier externe détecté : les touches déjà validées sont remises à zéro (comme le trackpad).
            if blocked { model.stop(); model.reset() } else { model.start() }
        }
    }

    private var testBody: some View {
        let layout = model.layout
        return TestScaffold(title: L("Keyboard", "Clavier"), instruction: instruction) {
            VStack(spacing: 16) {
                KeyboardCanvas(layout: layout, detected: model.detected, held: model.held, label: model.label(for:))
                    .frame(maxWidth: 900)
                HStack(spacing: 16) {
                    Text(L("\(model.detected.count) of \(layout.keyCount) keys detected", "\(model.detected.count) touches sur \(layout.keyCount) détectées"))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if let last = model.lastKey {
                        Text(L("Last: \(last)", "Dernière : \(last)"))
                            .foregroundStyle(.secondary)
                    }
                    InfoButton(L("A key stays gray? Press it firmly, alone. Some combinations (⌘ Tab, ⌘ Space) are taken by macOS: press each key on its own. Keys are identified by their position, so the test works with any layout (AZERTY, QWERTY, Arabic…).",
                                 "Une touche reste grise ? Appuyez franchement dessus, seule. Certaines combinaisons (⌘ Tab, ⌘ Espace) sont captées par macOS : appuyez sur chaque touche isolément. Les touches sont reconnues par leur position, le test marche donc avec toutes les dispositions (AZERTY, QWERTY, arabe…)."))
                    Spacer()
                    layoutPicker
                }
                .frame(maxWidth: 900)
                if showMissing && !model.missingKeys.isEmpty {
                    Callout(tint: .orange, symbol: "exclamationmark.triangle") {
                        Text(L("Not detected: ", "Non détectées : ") + model.missingKeys.map { missingName($0) }.joined(separator: ", "))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("Press them again, or finish if they really do not respond.", "Appuyez à nouveau dessus, ou terminez si elles ne répondent vraiment pas."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 900)
                }
            }
        } actions: {
            Button(L("Start Over", "Recommencer")) { model.reset(); showMissing = false }
            Button(L("Finish", "Terminer")) { complete() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var instruction: String {
        var text = L("Press every key, one at a time, without holding another key. Each key turns green when it is received.",
                     "Appuyez sur chaque touche, une à la fois, sans en maintenir une autre. Chaque touche passe au vert quand elle est reçue.")
        if model.topRow == .functionKeys {
            text += " " + L("For the top row, hold fn and press each key.", "Pour la rangée du haut, maintenez fn et appuyez sur chaque touche.")
        } else {
            text += " " + L("The Touch Bar has its own test, right after this one.", "La Touch Bar a son propre test, juste après celui-ci.")
        }
        return text
    }

    private var layoutPicker: some View {
        HStack(spacing: 8) {
            Text(L("Not your keyboard?", "Ce n'est pas votre clavier ?"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("", selection: $model.physical) {
                ForEach(PhysicalKeyboard.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            InfoButton(L("ISO (most of Europe): tall Return key over two rows and an extra key next to left Shift. ANSI (United States): wide Return key on one row. The drawing switches to ISO by itself when the ISO-only key is pressed.",
                         "ISO (la plupart des claviers européens, AZERTY compris) : touche Entrée haute sur deux rangées et touche en plus à côté de Maj gauche. ANSI (États-Unis) : touche Entrée large sur une rangée. Le dessin passe tout seul en ISO dès que la touche propre à l'ISO est pressée."))
            if !profile.isRecognized {
                Picker("", selection: $model.topRow) {
                    Text("F1–F12").tag(KeyboardTopRow.functionKeys)
                    Text("Touch Bar").tag(KeyboardTopRow.touchBar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
        }
    }

    private func missingName(_ key: KeyboardKey) -> String {
        let name = model.label(for: key)
        switch key.code {
        case 49: return L("space", "espace")
        case 56, 60: return L(key.code == 56 ? "left shift" : "right shift", key.code == 56 ? "maj gauche" : "maj droite")
        case 55, 54: return L(key.code == 55 ? "left command" : "right command", key.code == 55 ? "cmd gauche" : "cmd droite")
        case 58, 61: return L(key.code == 58 ? "left option" : "right option", key.code == 58 ? "option gauche" : "option droite")
        default: return name
        }
    }

    private func complete() {
        let layout = model.layout
        let missing = model.missingKeys
        if !missing.isEmpty && !showMissing {
            showMissing = true
            return
        }
        let summary = L("\(model.detected.count) of \(layout.keyCount) keys detected", "\(model.detected.count) touches sur \(layout.keyCount) détectées")
        let layoutText = "\(layout.physical.label) · \(layout.topRow == .touchBar ? "Touch Bar" : "F1–F12")"
        if missing.isEmpty {
            finish(TestResult(test: .keyboard, outcome: .passed, provenance: .measuredAuto, summary: summary, details: [layoutText]))
        } else if model.detected.isEmpty {
            finish(TestResult.notTested(.keyboard, reason: L("No key pressed", "Aucune touche pressée"), aborted: true))
        } else {
            // Des touches manquantes sont un problème, pas un simple point à surveiller.
            finish(TestResult(test: .keyboard, outcome: .failed, status: .problem, provenance: .measuredAuto, summary: summary,
                              details: [L("Not detected: ", "Non détectées : ") + missing.map { missingName($0) }.joined(separator: ", "), layoutText]))
        }
    }
}

/// Dessin du clavier à partir du modèle de disposition.
private struct KeyboardCanvas: View {
    let layout: KeyboardLayout
    let detected: Set<UInt16>
    let held: Set<UInt16>
    let label: (KeyboardKey) -> String

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / layout.width
            let gap = unit * 0.12
            ZStack(alignment: .topLeading) {
                ForEach(layout.decorations, id: \.self) { deco in
                    RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
                        .fill(deco.kind == .touchBar ? Color.black.opacity(0.85) : Color.secondary.opacity(0.18))
                        .overlay {
                            if deco.kind == .touchID {
                                Image(systemName: "touchid").foregroundStyle(.secondary).font(.system(size: unit * 0.3))
                            } else {
                                Text("Touch Bar").font(.system(size: unit * 0.22)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .frame(width: deco.w * unit - gap, height: deco.h * unit - gap)
                        .offset(x: deco.x * unit, y: deco.y * unit)
                }
                ForEach(layout.keys) { key in
                    let isDone = detected.contains(key.code)
                    let isHeld = held.contains(key.code)
                    RoundedRectangle(cornerRadius: unit * 0.14, style: .continuous)
                        .fill(isHeld ? Color.accentColor : (isDone ? Color.green.opacity(0.85) : Color.secondary.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: unit * 0.14, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(isDone ? 0 : 0.25)))
                        .overlay {
                            Text(label(key))
                                .font(.system(size: unit * (key.h < 0.7 ? 0.24 : 0.3), weight: .medium))
                                .foregroundStyle(isDone || isHeld ? Color.white : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(2)
                        }
                        .frame(width: key.w * unit - gap, height: key.h * unit - gap)
                        .offset(x: key.x * unit, y: key.y * unit)
                        .animation(.easeOut(duration: 0.12), value: isDone)
                        .accessibilityLabel(label(key))
                        .accessibilityValue(isDone ? L("detected", "détectée") : L("not detected", "non détectée"))
                }
            }
        }
        .aspectRatio(layout.width / layout.height, contentMode: .fit)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
    }
}
