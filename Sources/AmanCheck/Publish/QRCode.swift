import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// QR code généré sur le Mac avec CoreImage, sans dépendance (cahier des charges niveau 2, §4, §7).
/// Contenu : l'URL seule ; correction M ; marge blanche de 4 modules.
enum QRCode {
    static func image(for text: String, moduleSize: Int = 8) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }

        // CoreImage ajoute une marge d'un module : on la porte à 4 (zone de silence de la norme), sans lissage.
        let modules = cg.width
        let quiet = 3
        let side = (modules + 2 * quiet) * moduleSize
        guard let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: side, height: side))
        bitmap.interpolationQuality = .none
        bitmap.draw(cg, in: CGRect(x: quiet * moduleSize, y: quiet * moduleSize, width: modules * moduleSize, height: modules * moduleSize))
        guard let scaled = bitmap.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: side, height: side))
    }
}
