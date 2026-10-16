import SwiftUI
import LocalAuthentication
import AmanCore
import AmanDesign
import DiskHealthCore

/// Touch ID (spec §7.6) : demande d'authentification biométrique, succès ou échec mesurés.
struct TouchIDTestView: View {
    let finish: (TestResult) -> Void

    private enum State: Equatable { case ready, waiting, success, failed(String), notEnrolled, unavailable(String) }
    @SwiftUI.State private var state: State = .ready
    /// Sans empreinte enregistrée : vérifie toutes les 2 s si la personne en a ajouté une, pour reprendre seule.
    @SwiftUI.State private var enrollmentTimer: Timer?

    var body: some View {
        TestScaffold(title: "Touch ID",
                     instruction: L("Place a finger saved in Touch ID on the sensor (top right of the keyboard).",
                                    "Posez un doigt enregistré dans Touch ID sur le capteur (en haut à droite du clavier).")) {
            VStack(spacing: 18) {
                Image(systemName: "touchid")
                    .font(.system(size: 88, weight: .thin))
                    .foregroundStyle(symbolColor)
                    .amanPulse(isActive: state == .waiting)
                switch state {
                case .ready, .waiting:
                    HintRow(text: L("Use a finger already saved on this Mac. The test creates, changes and stores nothing.",
                                    "Utilisez un doigt déjà enregistré sur ce Mac. Le test ne crée, ne modifie et ne conserve rien."))
                case .success:
                    StatusLabel(.good, text: L("Fingerprint recognized", "Empreinte reconnue"), font: .headline)
                case .failed(let message):
                    StatusLabel(.watch, text: message, font: .headline)
                case .notEnrolled:
                    Callout(tint: .blue, symbol: "hand.raised") {
                        // Aucune interface ne lit le capteur sans empreinte enregistrée : c'est l'enclave sécurisée
                        // qui compare. Enregistrer une empreinte fait lire le capteur, et le test reprend seul ensuite.
                        Text(L("No fingerprint is saved on this Mac, and macOS only lets an app use Touch ID with a saved fingerprint. Adding one also tests the sensor: the Mac reads the finger several times.",
                               "Aucune empreinte n'est enregistrée sur ce Mac, et macOS ne laisse une app utiliser Touch ID qu'avec une empreinte enregistrée. En ajouter une teste aussi le capteur : le Mac lit le doigt plusieurs fois."))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("Add a fingerprint (the Mac's password is needed), then come back: the test continues by itself. It can be deleted afterwards.",
                               "Ajoutez une empreinte (le mot de passe du Mac est demandé), puis revenez : le test reprend tout seul. Elle peut être supprimée ensuite."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Open Touch ID Settings", "Ouvrir les réglages Touch ID")) { SystemSettingsPage.touchID.open() }
                    }
                case .unavailable(let message):
                    Callout(tint: .gray, symbol: "touchid") { Text(message) }
                }
            }
            .frame(maxWidth: 560)
        } actions: {
            switch state {
            case .success:
                Button(L("Continue", "Continuer")) {
                    finish(TestResult(test: .touchID, outcome: .passed, provenance: .measuredAuto,
                                      summary: L("Fingerprint recognized", "Empreinte reconnue")))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .notEnrolled:
                Button(L("Skip", "Passer")) {
                    finish(.notTested(.touchID, reason: L("No fingerprint saved", "Aucune empreinte enregistrée")))
                }
            case .unavailable:
                Button(L("Skip", "Passer")) {
                    finish(.notTested(.touchID, reason: L("Touch ID unavailable in this session", "Touch ID indisponible dans cette session")))
                }
                Button(L("Try Again", "Réessayer")) { authenticate() }
            case .failed:
                Button(L("The Sensor Does Not Respond", "Le capteur ne réagit pas")) {
                    finish(TestResult(test: .touchID, outcome: .failed, provenance: .measuredAuto,
                                      summary: L("Fingerprint not recognized", "Empreinte non reconnue")))
                }
                Button(L("Try Again", "Réessayer")) { authenticate() }
                    .buttonStyle(.borderedProminent)
            default:
                Button(L("Start", "Commencer")) { authenticate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state == .waiting)
            }
        }
        .onDisappear {
            enrollmentTimer?.invalidate()
            enrollmentTimer = nil
        }
    }

    private var symbolColor: Color {
        switch state {
        case .success: return .green
        case .failed: return .orange
        default: return AmanPalette.water
        }
    }

    /// Tant qu'aucune empreinte n'existe : surveille son ajout, puis lance la reconnaissance d'elle-même.
    private func watchEnrollment() {
        guard enrollmentTimer == nil else { return }
        enrollmentTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            MainActor.assumeIsolated {
                var error: NSError?
                guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
                timer.invalidate()
                enrollmentTimer = nil
                DiagnosticLog.shared.log("touchid", "empreinte ajoutée : reprise du test")
                NSApp.activate(ignoringOtherApps: true)
                authenticate()
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = ""   // pas de repli sur le mot de passe : on teste le capteur
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DiagnosticLog.shared.log("touchid", "indisponible : \(String(describing: error))")
            if let code = error.map({ LAError.Code(rawValue: $0.code) }), code == .biometryNotEnrolled {
                state = .notEnrolled
                watchEnrollment()
            } else {
                state = .unavailable(error?.localizedDescription ?? L("Touch ID is not available.", "Touch ID n'est pas disponible."))
            }
            return
        }
        state = .waiting
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: L("test the Touch ID sensor", "tester le capteur Touch ID")) { success, error in
            DispatchQueue.main.async {
                DiagnosticLog.shared.log("touchid", "résultat : \(success) \(String(describing: error))")
                if success {
                    state = .success
                } else if let la = error as? LAError, la.code == .userCancel || la.code == .systemCancel || la.code == .appCancel {
                    state = .ready
                } else {
                    state = .failed(L("Not recognized: try again with a saved finger.", "Non reconnue : réessayez avec un doigt enregistré."))
                }
            }
        }
    }
}
