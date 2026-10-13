import Foundation
import CommonCrypto

public enum DiskIdentity {
    public static func key(model: String, serial: String) -> String {
        let input = "\(model)|\(serial)"
        guard let data = input.data(using: .utf8) else { return "" }
        // SHA-256 from CommonCrypto, available on every macOS version (CryptoKit needs macOS 10.15,
        // Aman Legacy runs on 10.13). Same digest, so the same keys: LegacyCompatTests checks it.
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexStr = digest.map { String(format: "%02x", $0) }.joined()
        return String(hexStr.prefix(16))
    }
}
