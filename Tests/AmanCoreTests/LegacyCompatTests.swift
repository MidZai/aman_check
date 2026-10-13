import Testing
import Foundation
@testable import AmanCore

/// Sorties figées avant de rendre AmanCore compilable pour macOS 10.13 (Aman Legacy) :
/// le remplacement des API de macOS 10.15+ ne doit rien changer.
@Suite("Compatibilité Aman Legacy")
struct LegacyCompatTests {
    /// L'empreinte du rapport publié est recalculée par le serveur : elle doit rester un SHA-256 standard.
    @Test func reportFingerprintIsStandardSHA256() {
        #expect(ReportCoding.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(ReportCoding.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(ReportCoding.sha256(Data("Aman Check · rapport d'état".utf8)) == "7b2770f8d4875ec4b112b10350f423c97584d9e5d64b2bc7c20950a1e5fd681e")
    }
}
