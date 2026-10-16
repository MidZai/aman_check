import SwiftUI
import AppKit
import AVFoundation
import IOKit.audio
import AmanCore
import AmanDesign
import DiskHealthCore

/// Caméra (correctifs §6.4). Cause du bug précédent : le calque d'aperçu n'était dimensionné que dans
/// `updateNSView`, appelé avant la mise en page (cadre nul, jamais mis à jour) ; de plus l'app était signée
/// sans Hardened Runtime, donc sans l'entitlement caméra effectif. Ici : vue AppKit qui redimensionne
/// son calque dans `layout()`, session sur une file dédiée, comptage des images réellement reçues.
final class CameraSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum State: Equatable { case idle, denied, noCamera, running, failed(String) }

    @Published var state: State = .idle
    @Published var frames = 0
    @Published var brightness: Double?
    @Published var deviceName: String?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.aman.check.camera")
    private var frameCounter = 0
    /// Observateur d'erreur de session : retiré à l'arrêt et avant tout nouvel enregistrement (sinon il s'accumule à chaque ouverture du test).
    private var runtimeErrorObserver: NSObjectProtocol?

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        default:
            state = .denied
            return
        }
        // Caméra intégrée uniquement : pas une caméra externe ni l'iPhone (Continuité).
        let all = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        let devices = all.filter(Self.isBuiltInCamera)
        DiagnosticLog.shared.log("caméra", "caméras : \(all.map { "\($0.localizedName) [\($0.modelID), transport \($0.transportType)]" }) · intégrées : \(devices.map(\.localizedName))")
        guard let device = devices.first else { state = .noCamera; return }
        deviceName = device.localizedName

        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
        runtimeErrorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            DiagnosticLog.shared.log("caméra", "erreur de session : \(String(describing: error))")
            self?.state = .failed(error?.localizedDescription ?? "")
        }

        let session = self.session
        let started: Result<Void, Error> = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    session.beginConfiguration()
                    session.sessionPreset = .high
                    let input = try AVCaptureDeviceInput(device: device)
                    if session.canAddInput(input) { session.addInput(input) }
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    if session.canAddOutput(output) { session.addOutput(output) }
                    session.commitConfiguration()
                    session.startRunning()
                    continuation.resume(returning: .success(()))
                } catch {
                    session.commitConfiguration()
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch started {
        case .success:
            state = .running
            DiagnosticLog.shared.log("caméra", "session démarrée · en cours=\(session.isRunning)")
        case .failure(let error):
            state = .failed(error.localizedDescription)
            DiagnosticLog.shared.log("caméra", "échec : \(error)")
        }
    }

    /// Caméra intégrée. Sur les Mac Intel à puce T2, la caméra FaceTime passe par le bus USB interne de la T2 :
    /// son transport est « usb », pas « built-in » (constaté sur le MacBookPro16,1, modèle « UVC Camera
    /// VendorID_1452 ProductID_34068 ») ; l'ancien filtre la rejetait et le test concluait « pas de caméra ».
    /// Une caméra USB d'Apple n'est retenue que si son nom dit FaceTime (l'écran Studio Display, lui aussi
    /// d'Apple, a une caméra externe nommée autrement).
    static func isBuiltInCamera(_ device: AVCaptureDevice) -> Bool {
        if device.isContinuityCamera { return false }
        if device.transportType == Int32(kIOAudioDeviceTransportTypeBuiltIn) { return true }
        let isUSB = device.transportType == Int32(kIOAudioDeviceTransportTypeUSB)
        return isUSB && device.modelID.contains("VendorID_1452") && device.localizedName.localizedCaseInsensitiveContains("FaceTime")
    }

    func stop() {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
            self.runtimeErrorObserver = nil
        }
        let session = self.session
        queue.async { session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        // Luminosité moyenne une image sur 15 : image noire = caméra masquée ou défectueuse.
        guard frameCounter % 15 == 1, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            let count = frameCounter
            DispatchQueue.main.async { self.frames = count }
            return
        }
        let mean = Self.meanLuminance(pixels)
        let count = frameCounter
        DispatchQueue.main.async {
            self.frames = count
            self.brightness = mean
        }
    }

    static func meanLuminance(_ buffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: height, by: max(1, height / 40)) {
            for x in stride(from: 0, to: width, by: max(1, width / 40)) {
                let p = ptr + y * rowBytes + x * 4
                total += 0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])
                count += 1
            }
        }
        return count > 0 ? total / count / 255 : nil
    }
}

/// Vue d'aperçu : le calque suit la taille de la vue (`layout`), miroir comme FaceTime.
final class CameraPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> CameraPreviewNSView { CameraPreviewNSView(session: session) }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) { nsView.needsLayout = true }
}

struct CameraTestView: View {
    let finish: (TestResult) -> Void
    @StateObject private var camera = CameraSession()
    /// Aucune image après 8 secondes : la caméra est détectée mais n'envoie rien.
    @State private var noPictureAfterDelay = false

    var body: some View {
        TestScaffold(title: L("Camera", "Caméra"),
                     instruction: L("Look at the picture: is it sharp, without stains, lines or dead areas?",
                                    "Regardez l'image : est-elle nette, sans taches, lignes ni zones mortes ?")) {
            VStack(spacing: 14) {
                switch camera.state {
                case .denied:
                    PermissionDeniedView(subject: L("the camera", "à la caméra"), pane: "Privacy_Camera")
                case .noCamera:
                    Callout(tint: .gray, symbol: "video.slash") {
                        Text(L("No built-in camera was found.", "Aucune caméra intégrée n'a été trouvée."))
                    }
                case .failed(let message):
                    Callout(tint: .red, symbol: "exclamationmark.triangle") {
                        Text(L("The camera could not start.", "La caméra n'a pas pu démarrer.") + (message.isEmpty ? "" : " (\(message))"))
                    }
                case .idle, .running:
                    ZStack {
                        CameraPreview(session: camera.session)
                            .clipShape(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
                        if camera.frames == 0 {
                            ProgressView(L("Starting the camera…", "Démarrage de la caméra…"))
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .frame(maxWidth: 720)
                    HStack(spacing: 16) {
                        Label(camera.frames > 0 ? L("Picture received", "Image reçue") : L("Waiting for the picture…", "En attente de l'image…"),
                              systemImage: camera.frames > 0 ? "checkmark.circle.fill" : "hourglass")
                            .foregroundStyle(camera.frames > 0 ? Color.green : Color.secondary)
                        if let brightness = camera.brightness, brightness < 0.03 {
                            Label(L("Very dark picture: is the camera covered?", "Image très sombre : la caméra est-elle masquée ?"),
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if let name = camera.deviceName {
                            Text(name).foregroundStyle(.secondary)
                        }
                        if noPictureAfterDelay && camera.frames == 0 {
                            Label(L("The camera was found but sends no image.", "La caméra est détectée mais n'envoie aucune image."),
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.callout)
                    HintRow(text: L("Check sharpness, colors, stains on the lens and lines in the picture. Cover the camera with a finger: the picture must go dark, which proves it is live.",
                                    "Vérifiez la netteté, les couleurs, les taches sur l'objectif et les lignes dans l'image. Couvrez la caméra avec un doigt : l'image doit devenir noire, preuve qu'elle est en direct."))
                        .frame(maxWidth: 720)
                }
            }
        } actions: {
            switch camera.state {
            case .denied, .noCamera:
                Button(L("Skip", "Passer")) {
                    finish(.notTested(.camera, reason: camera.state == .denied ? L("Camera access refused", "Accès à la caméra refusé") : L("No camera", "Pas de caméra")))
                }
            case .failed(let message):
                Button(L("Record as Failed", "Noter comme défaillante")) {
                    finish(TestResult(test: .camera, outcome: .failed, provenance: .measuredAuto,
                                      summary: L("The camera does not start", "La caméra ne démarre pas"), details: [message]))
                }
            default:
                // La réponse négative reste toujours possible : seule la réponse positive attend une image.
                Button(L("No, There Is a Problem", "Non, il y a un problème")) { complete(ok: false) }
                Button(L("Yes, the Picture Is Good", "Oui, l'image est bonne")) { complete(ok: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(camera.frames == 0)
            }
        }
        .task { await camera.start() }
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if camera.frames == 0 { noPictureAfterDelay = true }
        }
        .onDisappear { camera.stop() }
    }

    private func complete(ok: Bool) {
        camera.stop()
        let details = [L("\(camera.frames) images received", "\(camera.frames) images reçues")]
            + (camera.brightness.map { [L("Mean brightness: \(Int($0 * 100)) %", "Luminosité moyenne : \(Int($0 * 100)) %")] } ?? [])
        if ok {
            finish(TestResult(test: .camera, outcome: .passed, provenance: .userObserved,
                              summary: L("Picture received and judged good", "Image reçue et jugée bonne"), details: details))
        } else {
            finish(TestResult(test: .camera, outcome: .failed, provenance: .userObserved,
                              summary: L("Defect seen in the picture", "Défaut constaté sur l'image"), details: details))
        }
    }
}
