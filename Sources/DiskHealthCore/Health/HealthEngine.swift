import Foundation

public enum HealthEngine {
    /// Below this remaining-life percentage, the drive becomes “Needs attention”.
    /// Same threshold as the ring turning red (brand guide: red at 25% and below): a red
    /// ring next to “Healthy” would be contradictory.
    public static let lowLifeThreshold = 25

    public static func evaluate(smart: NVMeSmartLog, identify: NVMeIdentify) -> HealthAssessment {
        var reasons: [String] = []
        var status: HealthStatus = .good

        // “Percentage used” can exceed 100: remaining life is then 0%.
        let healthPercent = max(0, 100 - Int(smart.percentageUsed))

        // Failures (bits 0, 2, 3 and 4 of “Critical Warning”).
        let spareReason = L("Spare capacity has dropped below the manufacturer's threshold.", "La réserve de secours est passée sous le seuil du fabricant.")
        if (smart.criticalWarning & 0b0001_1101) != 0 {
            status = .bad
            if (smart.criticalWarning & 0b0000_0001) != 0 { reasons.append(spareReason) }
            if (smart.criticalWarning & 0b0000_0100) != 0 { reasons.append(L("Drive reliability is degraded (internal errors).", "La fiabilité du disque est dégradée (erreurs internes).")) }
            if (smart.criticalWarning & 0b0000_1000) != 0 { reasons.append(L("The drive has switched to read-only mode.", "Le disque est passé en lecture seule.")) }
            if (smart.criticalWarning & 0b0001_0000) != 0 { reasons.append(L("Volatile memory backup has failed.", "La sauvegarde de la mémoire volatile a échoué.")) }
        }
        if smart.availableSpare < smart.availableSpareThreshold {
            status = .bad
            if !reasons.contains(spareReason) { reasons.append(spareReason) }
        }
        // Needs attention. These findings are listed even if the status is already “Likely failing”:
        // the user must see everything that's wrong, not just the most serious problem.
        var cautionReasons: [String] = []
        if smart.percentageUsed >= 100 {
            // Beyond 100%, the rated endurance is exceeded, but a failure isn't certain.
            cautionReasons.append(L("The manufacturer's rated endurance is fully used up (\(smart.percentageUsed)% used).", "L'endurance prévue par le fabricant est entièrement consommée (\(smart.percentageUsed) % utilisés)."))
        } else if healthPercent <= lowLifeThreshold {
            cautionReasons.append(L("Remaining life is low (\(healthPercent)%).", "La durée de vie restante est faible (\(healthPercent) %)."))
        }
        if smart.mediaErrors > 0 {
            cautionReasons.append(L("\(Formatters.integer(smart.mediaErrors)) uncorrected data error(s) detected.", "\(Formatters.integer(smart.mediaErrors)) erreur(s) de données non corrigée(s) détectée(s)."))
        }
        if !cautionReasons.isEmpty {
            if status == .good { status = .caution }
            reasons += cautionReasons
        }

        // Temperature doesn't count toward the health status: a short burst of heat (copy, test)
        // would flip the status and wrongly trigger “status change” alerts.
        // It has its own indicator and its own alert (5 min above the threshold).

        if status == .good {
            reasons.append(L("No problems detected.", "Aucune anomalie détectée."))
        }

        return HealthAssessment(status: status, healthPercent: healthPercent, reasons: reasons)
    }
}
