import Foundation

public struct NVMeSmartLog: Codable, Equatable, Hashable {
    public let criticalWarning: UInt8
    public let compositeTemperatureKelvin: UInt16
    public let availableSpare: UInt8
    public let availableSpareThreshold: UInt8
    public let percentageUsed: UInt8
    public let dataUnitsRead: UInt64
    public let dataUnitsWritten: UInt64
    public let hostReadCommands: UInt64
    public let hostWriteCommands: UInt64
    public let controllerBusyTimeMinutes: UInt64
    public let powerCycles: UInt64
    public let powerOnHours: UInt64
    public let unsafeShutdowns: UInt64
    public let mediaErrors: UInt64
    public let errorLogEntries: UInt64
    
    /// Composite temperature in °C, or nil when the drive reports nothing usable:
    /// 0 K, or a value outside −40 °C … 150 °C (e.g. 0xFFFF from a confused controller).
    public var temperatureCelsius: Int? {
        if compositeTemperatureKelvin == 0 { return nil }
        let celsius = Int(compositeTemperatureKelvin) - 273
        guard (-40...150).contains(celsius) else { return nil }
        return celsius
    }
    
    public init(criticalWarning: UInt8, compositeTemperatureKelvin: UInt16, availableSpare: UInt8, availableSpareThreshold: UInt8, percentageUsed: UInt8, dataUnitsRead: UInt64, dataUnitsWritten: UInt64, hostReadCommands: UInt64, hostWriteCommands: UInt64, controllerBusyTimeMinutes: UInt64, powerCycles: UInt64, powerOnHours: UInt64, unsafeShutdowns: UInt64, mediaErrors: UInt64, errorLogEntries: UInt64) {
        self.criticalWarning = criticalWarning
        self.compositeTemperatureKelvin = compositeTemperatureKelvin
        self.availableSpare = availableSpare
        self.availableSpareThreshold = availableSpareThreshold
        self.percentageUsed = percentageUsed
        self.dataUnitsRead = dataUnitsRead
        self.dataUnitsWritten = dataUnitsWritten
        self.hostReadCommands = hostReadCommands
        self.hostWriteCommands = hostWriteCommands
        self.controllerBusyTimeMinutes = controllerBusyTimeMinutes
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.errorLogEntries = errorLogEntries
    }
}
