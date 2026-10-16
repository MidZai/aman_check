import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Touch Bar : l'app affiche des zones numérotées sur toute la largeur ; chaque zone touchée passe au vert.
/// Vérifie à la fois l'affichage (les zones apparaissent) et le toucher (chaque zone réagit), sans autorisation.
/// La partie droite de la barre appartient à la Control Strip (luminosité, volume, Siri) : aucune interface
/// publique ne la masque, et 12 zones forcées sur 640 points débordaient dessous (constaté sur le MacBookPro16,1).
/// Les zones tiennent donc dans la partie de l'app, et l'extrémité droite se teste par le bouton volume de la
/// Control Strip : l'app voit le volume changer.
@MainActor
final class TouchBarModel: ObservableObject {
    static let zoneCount = 10
    @Published private(set) var touched: Set<Int> = []
    @Published private(set) var barShown = false
    /// Extrémité droite : le volume (ou la sourdine) a changé depuis l'ouverture du test.
    @Published private(set) var rightEndResponded = false
    /// `false` si le volume de la sortie ne se lit pas : l'étape n'est pas proposée.
    @Published private(set) var volumeReadable = true
    private var startLevel: (volume: Float?, muted: Bool?) = (nil, nil)
    private var timer: Timer?

    func startWatchingVolume() {
        startLevel = AudioDevices.outputLevel()
        volumeReadable = startLevel.volume != nil || startLevel.muted != nil
        guard volumeReadable, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkVolume() }
        }
    }

    func stopWatchingVolume() {
        timer?.invalidate()
        timer = nil
    }

    private func checkVolume() {
        let now = AudioDevices.outputLevel()
        let volumeMoved = zip2(now.volume, startLevel.volume).map { abs($0 - $1) >= 0.02 } ?? false
        let muteToggled = zip2(now.muted, startLevel.muted).map { $0 != $1 } ?? false
        if volumeMoved || muteToggled {
            rightEndResponded = true
            stopWatchingVolume()
            DiagnosticLog.shared.log("touchbar", "extrémité droite : volume \(String(describing: startLevel.volume)) → \(String(describing: now.volume)), sourdine \(String(describing: now.muted))")
        }
    }

    private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    func tap(_ index: Int) {
        touched.insert(index)
        DiagnosticLog.shared.log("touchbar", "zone \(index + 1) touchée")
    }

    func markShown() {
        guard !barShown else { return }
        barShown = true
        DiagnosticLog.shared.log("touchbar", "barre de l'app fournie au système")
    }

    func reset() {
        touched = []
        rightEndResponded = false
        stopWatchingVolume()
        startWatchingVolume()
    }
}

extension NSTouchBarItem.Identifier {
    static let amanZones = NSTouchBarItem.Identifier("com.aman.check.touchbar.zones")
}

/// Vue AppKit qui fournit la Touch Bar : elle doit être le premier répondeur de la fenêtre active.
final class TouchBarHostView: NSView, NSTouchBarDelegate {
    weak var model: TouchBarModel?
    private var buttons: [NSButton] = []

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
        // Aussi sur la fenêtre : la barre reste affichée même si SwiftUI déplace le premier répondeur.
        window.touchBar = makeTouchBar()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { window?.touchBar = nil }
        super.viewWillMove(toWindow: newWindow)
    }

    override func makeTouchBar() -> NSTouchBar? {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.amanZones]
        MainActor.assumeIsolated { model?.markShown() }
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == .amanZones else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        buttons = (0..<TouchBarModel.zoneCount).map { index in
            let button = NSButton(title: "\(index + 1)", target: self, action: #selector(tapped(_:)))
            button.tag = index
            button.bezelColor = NSColor(srgbRed: 0.18, green: 0.62, blue: 0.84, alpha: 1)
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 6
        // Largeur souple : au moins 520 points, jusqu'à 720 si la place existe, sans passer sous la Control Strip.
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        let preferred = stack.widthAnchor.constraint(equalToConstant: 720)
        preferred.priority = .defaultLow
        preferred.isActive = true
        item.view = stack
        return item
    }

    @objc private func tapped(_ sender: NSButton) {
        sender.bezelColor = .systemGreen
        MainActor.assumeIsolated { model?.tap(sender.tag) }
    }
}

private struct TouchBarHost: NSViewRepresentable {
    let model: TouchBarModel
    func makeNSView(context: Context) -> TouchBarHostView {
        let view = TouchBarHostView()
        view.model = model
        return view
    }
    func updateNSView(_ nsView: TouchBarHostView, context: Context) { nsView.model = model }
}

struct TouchBarTestView: View {
    let finish: (TestResult) -> Void
    @StateObject private var model = TouchBarModel()

    var body: some View {
        TestScaffold(title: "Touch Bar",
                     instruction: L("10 numbered zones appear on the Touch Bar. Touch each one with a finger: it turns green, here and on the bar. Then test the right end with the volume button.",
                                    "10 zones numérotées s'affichent sur la Touch Bar. Touchez-les une à une avec un doigt : elles passent au vert, ici et sur la barre. Testez ensuite l'extrémité droite avec le bouton du volume.")) {
            VStack(spacing: 22) {
                ZStack {
                    TouchBarHost(model: model).frame(width: 1, height: 1).opacity(0)
                    HStack(spacing: 6) {
                        ForEach(0..<TouchBarModel.zoneCount, id: \.self) { index in
                            let on = model.touched.contains(index)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? Color.green : AmanPalette.water.opacity(0.85))
                                .overlay(Text("\(index + 1)").font(.callout.weight(.semibold)).foregroundStyle(.white))
                                .frame(height: 34)
                                .animation(.easeOut(duration: 0.15), value: on)
                        }
                        if model.volumeReadable {
                            // Extrémité droite : la Control Strip (volume), testée par le changement de volume.
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.rightEndResponded ? Color.green : Color(white: 0.3))
                                .overlay(Image(systemName: "speaker.wave.2.fill").foregroundStyle(.white))
                                .frame(width: 70, height: 34)
                                .padding(.leading, 10)
                                .animation(.easeOut(duration: 0.15), value: model.rightEndResponded)
                        }
                    }
                    .padding(10)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: 820)
                }
                if model.volumeReadable {
                    NumberedSteps(steps: [
                        .init(text: L("Right end of the bar (sound, brightness, Siri): touch the volume button, then slide your finger left or right. The app sees the volume change.",
                                      "Extrémité droite de la barre (son, luminosité, Siri) : touchez le bouton du volume, puis faites glisser le doigt vers la gauche ou la droite. L'app voit le volume changer."))
                    ])
                    .frame(maxWidth: 640)
                }
                Text(L("\(model.touched.count) of \(TouchBarModel.zoneCount) zones touched", "\(model.touched.count) zones sur \(TouchBarModel.zoneCount) touchées")
                     + (model.volumeReadable ? (model.rightEndResponded ? L(" · right end responds", " · extrémité droite OK") : L(" · right end not tested yet", " · extrémité droite pas encore testée")) : ""))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                HintRow(text: L("Nothing on the Touch Bar? In System Settings > Keyboard > Touch Bar Settings, choose “Touch Bar shows: App Controls”, then come back here.",
                                "Rien sur la Touch Bar ? Dans Réglages Système › Clavier › Réglages de la Touch Bar, choisissez « La Touch Bar affiche : Commandes de l'app », puis revenez ici."))
                HintRow(text: L("Also look at the bar itself: lines, dead areas or uneven light are defects even if every zone reacts.",
                                "Regardez aussi la barre elle-même : lignes, zones mortes ou lumière inégale sont des défauts, même si toutes les zones réagissent."))
            }
            .frame(maxWidth: 820)
        } actions: {
            Button(L("Start Over", "Recommencer")) { model.reset() }
            Button(L("The Bar Shows Nothing", "La barre n'affiche rien")) {
                finish(TestResult(test: .touchBar, outcome: .failed, provenance: .userObserved,
                                  summary: L("Nothing displayed on the Touch Bar", "Rien ne s'affiche sur la Touch Bar"),
                                  details: [L("Check the “App Controls” setting before concluding.", "Vérifier le réglage « Commandes de l'app » avant de conclure.")]))
            }
            Button(L("Finish", "Terminer")) { complete() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { model.startWatchingVolume() }
        .onDisappear { model.stopWatchingVolume() }
    }

    private func complete() {
        let count = model.touched.count
        let total = TouchBarModel.zoneCount
        let summary = L("\(count) of \(total) zones respond", "\(count) zones sur \(total) réagissent")
        if count == 0 {
            finish(.notTested(.touchBar, reason: L("No zone touched", "Aucune zone touchée"), aborted: true))
            return
        }
        // Extrémité droite (Control Strip) : comptée seulement si le volume se lit sur ce Mac.
        let rightEndMissing = model.volumeReadable && !model.rightEndResponded
        var details: [String] = []
        if count < total {
            let missing = (0..<total).filter { !model.touched.contains($0) }.map { "\($0 + 1)" }.joined(separator: ", ")
            details.append(L("Zones not touched: \(missing)", "Zones non touchées : \(missing)"))
        }
        if rightEndMissing {
            details.append(L("Right end (volume button) not tested", "Extrémité droite (bouton du volume) non testée"))
        } else if model.rightEndResponded {
            details.append(L("Right end responds (volume changed from the Touch Bar)", "L'extrémité droite répond (volume changé depuis la Touch Bar)"))
        }
        let fullSummary = summary + (model.rightEndResponded ? L(" · right end responds", " · extrémité droite OK") : "")
        if count == total && !rightEndMissing {
            finish(TestResult(test: .touchBar, outcome: .passed, provenance: .measuredAuto, summary: fullSummary, details: details))
        } else {
            finish(TestResult(test: .touchBar, outcome: .failed, status: .watch, provenance: .measuredAuto, summary: fullSummary, details: details))
        }
    }
}

/// Ligne d'aide discrète, avec l'icône « i ».
struct HintRow: View {
    let text: String
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle").foregroundStyle(AmanPalette.water)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
