import Foundation

public enum ATASmartParser {
    public static func parseString(data: Data, range: Range<Int>) -> String {
        guard data.count >= range.upperBound else { return "" }
        var chars = [UInt8]()
        for i in stride(from: range.lowerBound, to: range.upperBound, by: 2) {
            chars.append(data[i+1])
            chars.append(data[i])
        }
        return String(bytes: chars, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // Compute the checksum using UInt to avoid any intermediate overflow.
    private static func verifyChecksum(_ data: Data) -> Bool {
        let sum = data.prefix(512).reduce(UInt(0)) { $0 + UInt($1) }
        return sum % 256 == 0
    }

    public static func parse(smartData: Data, thresholdsData: Data, identifyData: Data, statusExceeded: Bool) -> ATASmartSnapshot? {
        guard smartData.count >= 512, thresholdsData.count >= 512, identifyData.count >= 512 else {
            return nil
        }

        // Verify the checksums of both the SMART data and the thresholds.
        let checksumValid = verifyChecksum(smartData)
        let thresholdsChecksumValid = verifyChecksum(thresholdsData)

        var thresholdsMap = [UInt8: UInt8]()
        for i in 0..<30 {
            let offset = 2 + (i * 12)
            let id = thresholdsData[offset]
            if id != 0 {
                thresholdsMap[id] = thresholdsData[offset + 1]
            }
        }

        var attributes = [ATASmartAttribute]()
        for i in 0..<30 {
            let offset = 2 + (i * 12)
            let id = smartData[offset]
            if id != 0 {
                let flags = UInt16(smartData[offset+1]) | (UInt16(smartData[offset+2]) << 8)
                let current = smartData[offset+3]
                let worst = smartData[offset+4]
                let raw = Array(smartData[offset+5...offset+10])

                var rawValue: UInt64 = 0
                for j in 0..<6 {
                    rawValue |= (UInt64(raw[j]) << (j * 8))
                }

                let threshold = thresholdsMap[id] ?? 0

                attributes.append(ATASmartAttribute(
                    id: id,
                    flags: flags,
                    current: current,
                    worst: worst,
                    threshold: threshold,
                    raw: raw,
                    rawValue: rawValue
                ))
            }
        }

        let serialNumber = parseString(data: identifyData, range: 20..<40)
        let firmware = parseString(data: identifyData, range: 46..<54)
        let model = parseString(data: identifyData, range: 54..<94)

        let word217 = UInt16(identifyData[434]) | (UInt16(identifyData[435]) << 8)
        let rotationRate: Int
        if word217 == 1 {
            rotationRate = 1
        } else if word217 >= 0x0401 && word217 <= 0xFFFE {
            rotationRate = Int(word217)
        } else {
            rotationRate = 0
        }

        return ATASmartSnapshot(
            attributes: attributes.sorted { $0.id < $1.id },
            model: model,
            firmware: firmware,
            serialNumber: serialNumber,
            rotationRate: rotationRate,
            thresholdExceeded: statusExceeded,
            checksumValid: checksumValid,
            thresholdsChecksumValid: thresholdsChecksumValid
        )
    }
}
