import Foundation

public enum AttributeState: String, Codable {
    case normal
    case warning
    case critical
    case informational
}

public struct NVMeAttribute: Identifiable {
    public let id: UInt8
    public let name: String
    public let explanation: String
    public let displayValue: String
    public let rawValue: String
    public let state: AttributeState
    
    public init(id: UInt8, name: String, explanation: String, displayValue: String, rawValue: String, state: AttributeState) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.displayValue = displayValue
        self.rawValue = rawValue
        self.state = state
    }
}

public enum NVMeAttributeCatalog {
    private static func formatRaw(_ val: UInt64) -> String {
        return "0x\(String(format: "%02llX", val))"
    }
    
    public static func attributes(from log: NVMeSmartLog, identify: NVMeIdentify?) -> [NVMeAttribute] {
        var attrs: [NVMeAttribute] = []
        
        // 0x01: Critical warning
        let cwState: AttributeState
        if log.criticalWarning == 0 {
            cwState = .normal
        } else if log.criticalWarning == 1 << 1 {
            cwState = .warning // Only bit 1 active (temperature)
        } else {
            cwState = .critical
        }
        attrs.append(NVMeAttribute(id: 0x01, name: L("Critical warning", "Avertissement critique"), explanation: L("Warning flags raised by the drive controller. 0 means no warning is active.", "Indicateurs d'alerte envoyés par le contrôleur du disque. 0 signifie qu'aucune alerte n'est active."), displayValue: formatRaw(UInt64(log.criticalWarning)), rawValue: formatRaw(UInt64(log.criticalWarning)), state: cwState))
        
        // 0x02: Composite temperature
        let tempState: AttributeState
        let tStatus = TemperatureStatus.evaluate(temperatureCelsius: log.temperatureCelsius, identify: identify)
        switch tStatus {
        case .critical: tempState = .critical
        case .elevated: tempState = .warning
        default: tempState = .normal
        }
        let tempDisp = log.temperatureCelsius.map(Formatters.temperature) ?? "—"
        attrs.append(NVMeAttribute(id: 0x02, name: L("Composite temperature", "Température composite"), explanation: L("Overall drive temperature estimated by its controller.", "Température globale du disque estimée par son contrôleur."), displayValue: tempDisp, rawValue: formatRaw(UInt64(log.compositeTemperatureKelvin)), state: tempState))
        
        // 0x03: Available spare
        let resState: AttributeState
        if log.availableSpare < log.availableSpareThreshold {
            resState = .critical
        } else if log.availableSpare <= log.availableSpareThreshold + 10 && log.availableSpare < 100 && log.availableSpareThreshold < 90 {
            resState = .warning
        } else {
            resState = .normal
        }
        attrs.append(NVMeAttribute(id: 0x03, name: L("Available spare", "Réserve disponible"), explanation: L("Share of spare blocks still available to replace worn cells. It goes down as the drive ages.", "Part des blocs de secours encore disponibles pour remplacer les cellules usées. Elle diminue quand le disque vieillit."), displayValue: "\(log.availableSpare)\(Formatters.unitSpace)%", rawValue: formatRaw(UInt64(log.availableSpare)), state: resState))
        
        // 0x04: Available spare threshold
        attrs.append(NVMeAttribute(id: 0x04, name: L("Spare threshold", "Seuil de réserve"), explanation: L("Level set by the manufacturer. If available spare drops below it, the drive reports a critical state.", "Niveau fixé par le fabricant. Si la réserve disponible passe en dessous, le disque signale un état critique."), displayValue: "\(log.availableSpareThreshold)\(Formatters.unitSpace)%", rawValue: formatRaw(UInt64(log.availableSpareThreshold)), state: .informational))
        
        // 0x05: Percentage used
        let pctState: AttributeState
        if log.percentageUsed >= 100 - UInt8(HealthEngine.lowLifeThreshold) {
            pctState = .warning
        } else {
            pctState = .normal
        }
        attrs.append(NVMeAttribute(id: 0x05, name: L("Percentage used", "Pourcentage utilisé"), explanation: L("Manufacturer's estimate of how much rated endurance has been used. It can go above 100% without the drive failing right away.", "Estimation, par le fabricant, de la part de l'endurance déjà consommée. La valeur peut dépasser 100 % sans que le disque tombe en panne immédiatement."), displayValue: "\(log.percentageUsed)\(Formatters.unitSpace)%", rawValue: formatRaw(UInt64(log.percentageUsed)), state: pctState))
        
        // 0x06: Data units read
        attrs.append(NVMeAttribute(id: 0x06, name: L("Data read", "Données lues"), explanation: L("Total amount of data read since the drive was made.", "Volume total de données lues depuis la fabrication du disque."), displayValue: Formatters.dataUnitsToBytesText(log.dataUnitsRead), rawValue: formatRaw(log.dataUnitsRead), state: .informational))
        
        // 0x07: Data units written
        attrs.append(NVMeAttribute(id: 0x07, name: L("Data written", "Données écrites"), explanation: L("Total amount of data written since the drive was made. This is the main cause of SSD wear.", "Volume total de données écrites depuis la fabrication. C'est le principal facteur d'usure d'un SSD."), displayValue: Formatters.dataUnitsToBytesText(log.dataUnitsWritten), rawValue: formatRaw(log.dataUnitsWritten), state: .informational))
        
        // 0x08: Host read commands
        attrs.append(NVMeAttribute(id: 0x08, name: L("Read commands", "Commandes de lecture"), explanation: L("Number of read commands handled by the controller.", "Nombre de commandes de lecture traitées par le contrôleur."), displayValue: Formatters.integer(log.hostReadCommands), rawValue: formatRaw(log.hostReadCommands), state: .informational))
        
        // 0x09: Host write commands
        attrs.append(NVMeAttribute(id: 0x09, name: L("Write commands", "Commandes d'écriture"), explanation: L("Number of write commands handled by the controller.", "Nombre de commandes d'écriture traitées par le contrôleur."), displayValue: Formatters.integer(log.hostWriteCommands), rawValue: formatRaw(log.hostWriteCommands), state: .informational))
        
        // 0x0A: Controller busy time
        attrs.append(NVMeAttribute(id: 0x0A, name: L("Controller busy time", "Temps d'activité du contrôleur"), explanation: L("Time, in minutes, the controller spent handling commands. Some Apple drives always report 0.", "Temps, en minutes, pendant lequel le contrôleur a traité des commandes. Certains disques Apple indiquent toujours 0."), displayValue: "\(Formatters.integer(log.controllerBusyTimeMinutes))\(Formatters.unitSpace)min", rawValue: formatRaw(log.controllerBusyTimeMinutes), state: .informational))
        
        // 0x0B: Power cycles
        attrs.append(NVMeAttribute(id: 0x0B, name: L("Power cycles", "Cycles d'allumage"), explanation: L("Number of times the drive was powered on.", "Nombre de fois où le disque a été mis sous tension."), displayValue: Formatters.integer(log.powerCycles), rawValue: formatRaw(log.powerCycles), state: .informational))
        
        // 0x0C: Power-on hours
        attrs.append(NVMeAttribute(id: 0x0C, name: L("Power-on hours", "Heures d'allumage"), explanation: L("Total time the drive has been powered on.", "Durée totale de fonctionnement du disque."), displayValue: Formatters.hours(log.powerOnHours), rawValue: formatRaw(log.powerOnHours), state: .informational))
        
        // 0x0D: Unsafe shutdowns
        attrs.append(NVMeAttribute(id: 0x0D, name: L("Unsafe shutdowns", "Arrêts non propres"), explanation: L("Number of power losses without a normal shutdown (crash, dead battery, holding the power button). A non-zero value is common and usually harmless.", "Nombre de coupures d'alimentation sans arrêt normal (plantage, batterie vide, bouton maintenu). Une valeur non nulle est courante et généralement sans gravité."), displayValue: Formatters.integer(log.unsafeShutdowns), rawValue: formatRaw(log.unsafeShutdowns), state: .informational))
        
        // 0x0E: Media and data integrity errors
        // Same level as the health engine (“Needs attention”), not “Critical”.
        let mediaState: AttributeState = log.mediaErrors > 0 ? .warning : .normal
        attrs.append(NVMeAttribute(id: 0x0E, name: L("Media and data integrity errors", "Erreurs média et intégrité"), explanation: L("Data errors the controller could not correct. Any value above 0 is worth watching, and a good reason to back up your data.", "Erreurs de données que le contrôleur n'a pas pu corriger. Toute valeur supérieure à 0 mérite d'être surveillée et de sauvegarder vos données."), displayValue: Formatters.integer(log.mediaErrors), rawValue: formatRaw(log.mediaErrors), state: mediaState))
        
        // 0x0F: Number of error log entries
        attrs.append(NVMeAttribute(id: 0x0F, name: L("Error log entries", "Entrées du journal d'erreurs"), explanation: L("Number of entries in the controller's error log. A non-zero value is common and doesn't necessarily mean there's a problem.", "Nombre d'entrées dans le journal d'erreurs du contrôleur. Une valeur non nulle est fréquente et n'indique pas forcément un problème."), displayValue: Formatters.integer(log.errorLogEntries), rawValue: formatRaw(log.errorLogEntries), state: .informational))
        
        return attrs
    }
}
