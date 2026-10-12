import Foundation
import CryptoKit

public enum DiskIdentity {
    public static func key(model: String, serial: String) -> String {
        let input = "\(model)|\(serial)"
        guard let data = input.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        let hexStr = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hexStr.prefix(16))
    }
}
