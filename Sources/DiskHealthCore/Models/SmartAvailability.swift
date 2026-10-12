import Foundation

public enum SmartAvailability: Equatable, Hashable, Codable, Sendable {
    case available                  // S.M.A.R.T. is readable
    case disabledOnDrive            // S.M.A.R.T. disabled on drive
    case notSupportedByEnclosure    // USB enclosure does not pass S.M.A.R.T.
    case driverRequired             // A third-party driver could enable it (Phase 5)
    case error(code: Int32)         // IOKit error with code
}
