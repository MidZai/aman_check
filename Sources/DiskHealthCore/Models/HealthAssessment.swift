import Foundation

public enum HealthStatus: String, Codable {
    case good
    case caution
    case bad
    case unknown
}

public struct HealthAssessment: Codable, Equatable {
    public let status: HealthStatus
    public let healthPercent: Int?
    public let reasons: [String]
    
    public init(status: HealthStatus, healthPercent: Int?, reasons: [String]) {
        self.status = status
        self.healthPercent = healthPercent
        self.reasons = reasons
    }
}
