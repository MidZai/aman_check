import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Cause du bug précédent : les contacts (`NSTouch`) ne sont envoyés qu'à une `NSView` qui les accepte
/// (`allowedTouchTypes`) ; un moniteur d'événements global n'en reçoit aucun. Ici, une vue AppKit dédiée
/// reçoit clics, défilement, pincement, rotation, pression et contacts (correctifs §6.3).
@MainActor
final class TrackpadModel: ObservableObject {
    static let columns = 8
    static let rows = 5

    enum Gesture: String, CaseIterable, Identifiable {
        case click, secondaryClick, scroll, pinch, rotate, forceClick
        var id: String { rawValue }

        var title: String {
            switch self {
            case .click: return L("Click", "Clic")
            case .secondaryClick: return L("Secondary click (two fingers)", "Clic secondaire (deux doigts)")
            case .scroll: return L("Two-finger scroll", "Défilement à deux doigts")
            case .pinch: return L("Pinch to zoom", "Pincement pour zoomer")
            case .rotate: return L("Rotate with two fingers", "Rotation à deux doigts")
            case .forceClick: return L("Force click (press harder)", "Clic forcé (appuyez plus fort)")
            }
        }

        /// Consigne courte, affichée tant que le geste n'est pas reçu.
        var howTo: String {
            switch self {
            case .click: return L("Press the trackpad until it clicks.", "Appuyez sur le trackpad jusqu'au « clic ».")
            case .secondaryClick: return L("Click with two fingers at the same time.", "Cliquez avec deux doigts posés en même temps.")
            case .scroll: return L("Slide two fingers up or down.", "Glissez deux doigts vers le haut ou le bas.")
            case .pinch: return L("Spread or pinch two fingers, as to zoom a photo.", "Écartez ou rapprochez deux doigts, comme pour zoomer une photo.")
            case .rotate: return L("Turn two fingers around, like a volume knob.", "Faites tourner deux doigts, comme un bouton de volume.")
            case .forceClick: return L("Click, then press harder until a second click.", "Cliquez, puis appuyez plus fort jusqu'au second déclic.")
            }
        }

        /// Explication détaillée (bouton « i »).
        var help: String {
            switch self {
            case .click:
                return L("A firm press with one finger, pointer in the gray area. You should feel and hear a click.",
                         "Un appui franc avec un doigt, pointeur dans la zone grise. Vous devez sentir et entendre un clic.")
            case .secondaryClick:
                return L("Put two fingers on the trackpad and click. If nothing happens, the secondary click may be set differently in System Settings > Trackpad; Control-click also works.",
                         "Posez deux doigts sur le trackpad et cliquez. Si rien ne se passe, le clic secondaire est peut-être réglé autrement dans Réglages Système › Trackpad ; Ctrl + clic fonctionne aussi.")
            case .scroll:
                return L("Two fingers flat on the trackpad, slide them together up or down, without clicking.",
                         "Deux doigts à plat sur le trackpad, faites-les glisser ensemble vers le haut ou le bas, sans cliquer.")
            case .pinch:
                return L("Put your thumb and index finger on the trackpad, then spread them apart or bring them together.",
                         "Posez le pouce et l'index sur le trackpad, puis écartez-les ou rapprochez-les.")
            case .rotate:
                return L("Keep two fingers (thumb and index) on the trackpad and move them in a small arc around a central point, as if turning a photo or a knob. Rotating a few degrees is enough.",
                         "Gardez deux doigts (pouce et index) sur le trackpad et faites-leur décrire un petit arc de cercle autour d'un point central, comme pour faire pivoter une photo ou tourner un bouton. Quelques degrés suffisent.")
            case .forceClick:
                return L("On Force Touch trackpads, pressing harder after the click gives a second, deeper click. If “Force Click and haptic feedback” is off in System Settings > Trackpad, this gesture is not detected.",
                         "Sur les trackpads Force Touch, appuyer plus fort après le clic produit un second clic, plus profond. Si « Clic forcé et retour haptique » est désactivé dans Réglages Système › Trackpad, ce geste n'est pas détecté.")
            }
        }

        var symbol: String {
            switch self {
            case .click: return "hand.tap"
            case .secondaryClick: return "hand.tap.fill"
            case .scroll: return "arrow.up.and.down"
            case .pinch: return "arrow.down.left.and.arrow.up.right"
            case .rotate: return "arrow.clockwise"
            case .forceClick: return "hand.point.up.left.and.text"
            }
        }
    }

    let gestures: [Gesture]
    @Published private(set) var done: Set<Gesture> = []
    @Published private(set) var cells: Set<Int> = []
    @Published private(set) var touches: [CGPoint] = []

    init(forceTouch: Bool) {
        gestures = Gesture.allCases.filter { forceTouch || $0 != .forceClick }
    }

    var coverage: Double { Double(cells.count) / Double(Self.columns * Self.rows) }
    var isComplete: Bool { done.isSuperset(of: gestures) && cells.count == Self.columns * Self.rows }

    func reset() {
        done = []
        cells = []
        touches = []
    }

    func mark(_ gesture: Gesture) {
        guard !done.contains(gesture) else { return }
        done.insert(gesture)
        DiagnosticLog.shared.log("trackpad", "geste reçu : \(gesture.rawValue)")
    }

    /// Positions normalisées (0…1, origine en bas à gauche) des doigts sur le trackpad physique.
    func update(touches points: [CGPoint]) {
        touches = points
        for p in points {
            let c = min(Self.columns - 1, max(0, Int(p.x * Double(Self.columns))))
            let r = min(Self.rows - 1, max(0, Int((1 - p.y) * Double(Self.rows))))
            cells.insert(r * Self.columns + c)
        }
    }
}

/// Vue AppKit qui reçoit tous les événements du trackpad.
final class TrackpadCaptureView: NSView {
    weak var model: TrackpadModel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
        // Pression (Force Touch) : configuration nécessaire pour recevoir le 2ᵉ niveau.
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDefault)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        DiagnosticLog.shared.log("trackpad", "vue installée · touches acceptées=\(allowedTouchTypes.rawValue)")
    }

    private func send(_ touchesEvent: NSEvent) {
        let points = touchesEvent.touches(matching: .touching, in: self).map(\.normalizedPosition)
        MainActor.assumeIsolated { model?.update(touches: points) }
    }

    override func touchesBegan(with event: NSEvent) { send(event) }
    override func touchesMoved(with event: NSEvent) { send(event) }
    override func touchesEnded(with event: NSEvent) { send(event) }
    override func touchesCancelled(with event: NSEvent) { send(event) }

    override func mouseDown(with event: NSEvent) {
        let gesture: TrackpadModel.Gesture = event.modifierFlags.contains(.control) ? .secondaryClick : .click
        MainActor.assumeIsolated { model?.mark(gesture) }
    }

    override func rightMouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { model?.mark(.secondaryClick) }
    }

    override func scrollWheel(with event: NSEvent) {
        // Défilement précis = trackpad (une molette de souris n'a pas de deltas précis).
        guard event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 0.5 else { return }
        MainActor.assumeIsolated { model?.mark(.scroll) }
    }

    override func magnify(with event: NSEvent) {
        MainActor.assumeIsolated { model?.mark(.pinch) }
    }

    override func rotate(with event: NSEvent) {
        MainActor.assumeIsolated { model?.mark(.rotate) }
    }

    override func pressureChange(with event: NSEvent) {
        if event.stage >= 2 {
            MainActor.assumeIsolated { model?.mark(.forceClick) }
        }
    }
}

private struct TrackpadCaptureRepresentable: NSViewRepresentable {
    let model: TrackpadModel

    func makeNSView(context: Context) -> TrackpadCaptureView {
        let view = TrackpadCaptureView(frame: .zero)
        view.model = model
        return view
    }

    func updateNSView(_ nsView: TrackpadCaptureView, context: Context) {
        nsView.model = model
    }
}

struct TrackpadTestView: View {
    let profile: DeviceProfile
    let finish: (TestResult) -> Void
    @StateObject private var model: TrackpadModel
    @StateObject private var gate: ExternalInputMonitor

    init(profile: DeviceProfile, finish: @escaping (TestResult) -> Void) {
        self.profile = profile
        self.finish = finish
        _model = StateObject(wrappedValue: TrackpadModel(forceTouch: profile.trackpadForceTouch))
        _gate = StateObject(wrappedValue: ExternalInputMonitor(test: .trackpad, active: profile.hasBuiltInTrackpad))
    }

    var body: some View {
        // Une souris ou un trackpad externe pourrait valider les gestes : le test ne démarre pas.
        Group {
            if gate.isBlocked {
                ExternalInputBlockedView(test: .trackpad, blockers: gate.blockers, finish: finish)
            } else {
                testBody
            }
        }
        .onAppear { gate.start() }
        .onDisappear { gate.stop() }
        .onChange(of: gate.isBlocked) { blocked in
            if blocked { model.reset() }
        }
    }

    private var testBody: some View {
        TestScaffold(title: L("Trackpad", "Trackpad"),
                     instruction: (profile.hasBuiltInTrackpad ? "" : L("Test the trackpad that comes with this Mac (a mouse cannot do the gestures). ",
                                                                        "Testez le trackpad vendu avec ce Mac (une souris ne peut pas faire les gestes). "))
                        + L("Put the pointer in the gray area, then slide a finger over the whole trackpad until every square lights up. Then do each gesture in the list.",
                            "Placez le pointeur dans la zone grise, puis passez un doigt sur tout le trackpad jusqu'à allumer toutes les cases. Faites ensuite chaque geste de la liste.")) {
            HStack(alignment: .top, spacing: 24) {
                ZStack {
                    TrackpadCaptureRepresentable(model: model)
                    surface.allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.gestures) { gesture in
                        let done = model.done.contains(gesture)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : gesture.symbol)
                                .foregroundStyle(done ? Color.green : AmanPalette.water)
                                .font(.title3)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gesture.title).fontWeight(.medium)
                                if !done {
                                    Text(gesture.howTo)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            InfoButton(gesture.help)
                        }
                        .animation(.easeOut(duration: 0.15), value: done)
                    }
                    Divider()
                    HStack {
                        Text(L("Surface covered: \(Int((model.coverage * 100).rounded()))\(Formatters.unitSpace)%",
                               "Surface couverte : \(Int((model.coverage * 100).rounded()))\(Formatters.unitSpace)%"))
                            .font(.headline)
                            .monospacedDigit()
                        Spacer()
                        InfoButton(L("Slide one finger over the whole trackpad, edges and corners included. The pointer may leave the gray area as long as your finger stays on the trackpad. A square that never lights up may be a dead zone.",
                                     "Faites glisser un doigt sur tout le trackpad, bords et coins compris. Le pointeur peut sortir de la zone grise tant que le doigt reste posé. Une case qui ne s'allume jamais peut signaler une zone morte."))
                    }
                }
                .frame(width: 330)
                .padding(16)
                .background(AmanDesign.cardBackground, in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(AmanDesign.cardBorder))
            }
        } actions: {
            Button(L("Start Over", "Recommencer")) { model.reset() }
            Button(L("Finish", "Terminer")) { complete() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Rectangle du trackpad (format 16:10), grille de couverture et doigts en direct.
    private var surface: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * 1.6)
            let height = width / 1.6
            let cw = width / CGFloat(TrackpadModel.columns)
            let ch = height / CGFloat(TrackpadModel.rows)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                ForEach(0..<(TrackpadModel.columns * TrackpadModel.rows), id: \.self) { index in
                    let on = model.cells.contains(index)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? AmanPalette.water.opacity(0.75) : Color.secondary.opacity(0.10))
                        .frame(width: cw - 6, height: ch - 6)
                        .offset(x: CGFloat(index % TrackpadModel.columns) * cw + 3, y: CGFloat(index / TrackpadModel.columns) * ch + 3)
                        .animation(.easeOut(duration: 0.2), value: on)
                }
                ForEach(Array(model.touches.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .overlay(Circle().strokeBorder(AmanPalette.ink, lineWidth: 2))
                        .frame(width: 26, height: 26)
                        .offset(x: p.x * width - 13, y: (1 - p.y) * height - 13)
                }
            }
            .frame(width: width, height: height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func complete() {
        let total = TrackpadModel.columns * TrackpadModel.rows
        let accessory = profile.hasBuiltInTrackpad ? [] : accessoryDetail(for: .trackpad)
        let missing = model.gestures.filter { !model.done.contains($0) }
        let summary = L("\(model.gestures.count - missing.count) of \(model.gestures.count) gestures · \(Int((model.coverage * 100).rounded()))% of the surface",
                        "\(model.gestures.count - missing.count) gestes sur \(model.gestures.count) · \(Int((model.coverage * 100).rounded())) % de la surface")
        if model.done.isEmpty && model.cells.isEmpty {
            finish(.notTested(.trackpad, reason: L("Nothing received", "Rien reçu"), aborted: true))
        } else if model.isComplete {
            finish(TestResult(test: .trackpad, outcome: .passed, provenance: .measuredAuto, summary: summary, details: accessory))
        } else {
            var details: [String] = []
            if !missing.isEmpty { details.append(L("Not received: ", "Non reçus : ") + missing.map(\.title).joined(separator: ", ")) }
            if model.cells.count < total { details.append(L("\(total - model.cells.count) squares never touched", "\(total - model.cells.count) cases jamais touchées")) }
            finish(TestResult(test: .trackpad, outcome: .failed, status: .watch, provenance: .measuredAuto, summary: summary, details: details + accessory))
        }
    }
}
