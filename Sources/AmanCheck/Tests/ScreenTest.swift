import SwiftUI
import AppKit
import AmanCore
import AmanDesign
import DiskHealthCore

/// Fenêtre sans bordure capable de recevoir le clavier : par défaut, une fenêtre `.borderless`
/// ne devient jamais « key » et Espace / flèches / Échap ne lui parviennent pas (correctifs §6.1).
final class FullscreenTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Vue plein cadre : couleur unie sur 100 % de l'écran, sans marge ni zone de sécurité.
final class ColorFillView: NSView {
    var onKey: ((NSEvent) -> Void)?
    var onClick: (() -> Void)?
    private let indicator = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        indicator.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        indicator.textColor = .white
        indicator.alignment = .center
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        indicator.layer?.cornerRadius = 8
        addSubview(indicator)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    func show(color: NSColor, index: Int, count: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color.cgColor
        CATransaction.commit()
        indicator.stringValue = "\(index + 1) / \(count)"
        indicator.sizeToFit()
        let size = NSSize(width: indicator.frame.width + 20, height: 28)
        indicator.frame = NSRect(x: (bounds.width - size.width) / 2, y: 40, width: size.width, height: size.height)
        indicator.alphaValue = 1
        // Indicateur discret qui disparaît après 2 s.
        let token = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.currentToken == token else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                self.indicator.animator().alphaValue = 0
            }
        }
        currentToken = token
    }

    private var currentToken = -1
}

/// Pilote du test plein écran.
@MainActor
final class ScreenTestRunner {
    static let colors: [(NSColor, String)] = [
        (.white, "blanc"), (.black, "noir"), (NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), "rouge"),
        (NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), "vert"), (NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), "bleu"),
        (NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), "gris")
    ]

    private var window: FullscreenTestWindow?
    private var view: ColorFillView?
    private var index = 0
    private var maxIndexShown = 0
    private var previousOptions: NSApplication.PresentationOptions = []
    private var completion: ((_ allShown: Bool) -> Void)?

    /// Écran intégré par défaut (spec §7.1), sinon l'écran de la fenêtre de l'app.
    static func targetScreen() -> NSScreen? {
        let builtIn = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
        return builtIn ?? NSApp.keyWindow?.screen ?? NSScreen.main
    }

    func start(completion: @escaping (_ allShown: Bool) -> Void) {
        guard let screen = Self.targetScreen() else { completion(false); return }
        self.completion = completion
        index = 0
        maxIndexShown = 0

        let window = FullscreenTestWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered,
                                          defer: false, screen: screen)
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.setFrame(screen.frame, display: true)

        let view = ColorFillView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        view.onKey = { [weak self] event in self?.handle(event) }
        view.onClick = { [weak self] in self?.advance() }
        window.contentView = view

        previousOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.hide()

        self.window = window
        self.view = view
        DiagnosticLog.shared.log("écran", "début · écran \(screen.localizedName) \(Int(screen.frame.width))×\(Int(screen.frame.height)) · fenêtre \(window.frame) · key=\(window.isKeyWindow)")
        show()
    }

    private func show() {
        let (color, name) = Self.colors[index]
        maxIndexShown = max(maxIndexShown, index)
        view?.show(color: color, index: index, count: Self.colors.count)
        DiagnosticLog.shared.log("écran", "couleur \(index + 1)/\(Self.colors.count) : \(name)")
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 49, 124, 36: advance()       // Espace, →, Entrée
        case 123: goBack()                // ←
        case 53: close(allShown: false)   // Échap
        default: break
        }
    }

    private func advance() {
        if index + 1 < Self.colors.count {
            index += 1
            show()
        } else {
            close(allShown: maxIndexShown == Self.colors.count - 1)
        }
    }

    private func goBack() {
        guard index > 0 else { return }
        index -= 1
        show()
    }

    private func close(allShown: Bool) {
        // Tout est rétabli : curseur, Dock, barre de menus.
        NSCursor.unhide()
        NSApp.presentationOptions = previousOptions
        window?.orderOut(nil)
        window = nil
        view = nil
        DiagnosticLog.shared.log("écran", "fin · toutes les couleurs affichées : \(allShown)")
        completion?(allShown)
        completion = nil
    }
}

/// Étapes du test d'écran dans l'assistant.
struct ScreenTestView: View {
    let finish: (TestResult) -> Void

    @State private var runner: ScreenTestRunner?
    @State private var allShown = false
    @State private var interrupted = false
    @State private var sawDefect = false
    @State private var defectNote = ""

    var body: some View {
        TestScaffold(title: L("Display", "Écran"),
                     instruction: allShown
                        ? L("Did you see dead pixels, stains or darker areas?", "Avez-vous vu des points morts, des taches ou des zones plus sombres ?")
                        : L("Set the brightness to maximum, clean the screen and move closer. Six solid colors will fill the whole screen.",
                            "Réglez la luminosité au maximum, nettoyez l'écran et approchez-vous. Six couleurs unies vont remplir tout l'écran.")) {
            VStack(spacing: 20) {
                if allShown {
                    answerForm
                } else {
                    preview
                }
            }
        } actions: {
            if allShown {
                Button(L("Run Again", "Recommencer")) { start() }
                if sawDefect {
                    Button(L("Confirm the Defect", "Confirmer le défaut")) {
                        finish(TestResult(test: .screen, outcome: .failed, provenance: .userObserved,
                                          summary: L("Defect seen by the user", "Défaut constaté par l'utilisateur"),
                                          details: defectNote.isEmpty ? [] : [defectNote]))
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(L("Yes, I Saw Something", "Oui, j'ai vu un défaut")) { sawDefect = true }
                    Button(L("No, the Screen Is Uniform", "Non, l'écran est uniforme")) {
                        finish(TestResult(test: .screen, outcome: .passed, provenance: .userObserved,
                                          summary: L("No defect seen on 6 colors", "Aucun défaut constaté sur 6 couleurs")))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button(L("Start", "Commencer")) { start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                ForEach(Array(ScreenTestRunner.colors.enumerated()), id: \.offset) { _, entry in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: entry.0))
                        .frame(width: 64, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                keyHint("space", L("Space, → or a click: next color", "Espace, → ou un clic : couleur suivante"))
                keyHint("arrow.left", L("←: previous color", "← : couleur précédente"))
                keyHint("escape", L("Esc: stop", "Échap : arrêter"))
                keyHint("info.circle", L("On a Mac with a notch, the area around the camera is not part of the display.",
                                          "Sur un Mac avec encoche, la zone autour de la caméra ne fait pas partie de l'écran."))
            }
            .frame(maxWidth: 520, alignment: .leading)
            if interrupted {
                StatusPill(.watch, text: L("Interrupted: all colors must be shown", "Interrompu : toutes les couleurs doivent être affichées"))
            }
        }
    }

    private var answerForm: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(AmanPalette.water)
            if sawDefect {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Where? (optional)", "Où ? (facultatif)")).font(.headline)
                    TextField(L("e.g. white dot at the top left, stain in the center", "ex. point blanc en haut à gauche, tache au centre"),
                              text: $defectNote)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 520)
            }
        }
    }

    private func keyHint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
    }

    private func start() {
        sawDefect = false
        let runner = ScreenTestRunner()
        self.runner = runner
        runner.start { shown in
            allShown = shown
            interrupted = !shown
            self.runner = nil
        }
    }
}
