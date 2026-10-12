import Foundation

public enum ATAHealthEvaluator {
    public static func evaluate(snapshot: ATASmartSnapshot) -> HealthAssessment {
        let profile = ATACatalog.profile(for: snapshot.model)
        let metrics = DiskMetrics(snapshot: .ata(snapshot))
        let lifeRemaining = metrics.lifeRemainingPercent

        var reasons = [String]()
        var status = HealthStatus.good

        // Failing.
        if snapshot.thresholdExceeded {
            status = .bad
            reasons.append(L("The drive itself reports an imminent failure (S.M.A.R.T. status).", "Le disque signale lui-même une défaillance imminente (statut S.M.A.R.T.)."))
        }
        for attr in snapshot.attributes where attr.threshold > 0 && attr.current <= attr.threshold {
            status = .bad
            let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
            reasons.append(L("The “\(info.name)” attribute has dropped below its failure threshold.", "L'attribut « \(info.name) » est passé sous son seuil de défaillance."))
        }

        // Needs attention (listed even if the status is already “Likely failing”).
        var cautionReasons: [String] = []
        for attr in snapshot.attributes {
            let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
            switch info.role {
            case .reallocated, .pending, .uncorrectable:
                if let raw = attr.value(for: info.role), raw > 0 {
                    cautionReasons.append(L("\(info.name): \(Formatters.integer(raw)).", "\(info.name) : \(Formatters.integer(raw))."))
                }
            default:
                // Threshold crossed in the past, but not anymore (otherwise it's already “failing”).
                if attr.threshold > 0 && attr.worst <= attr.threshold && attr.current > attr.threshold {
                    cautionReasons.append(L("The “\(info.name)” attribute crossed its threshold in the past.", "L'attribut « \(info.name) » a déjà franchi son seuil par le passé."))
                }
            }
        }
        if let life = lifeRemaining, life <= HealthEngine.lowLifeThreshold {
            cautionReasons.append(L("Estimated remaining life is low (\(life)%).", "La durée de vie restante estimée est faible (\(life) %)."))
        }
        if !cautionReasons.isEmpty {
            if status == .good { status = .caution }
            reasons += cautionReasons
        }

        // Temperature doesn't count toward the health status (see HealthEngine).

        if status == .good {
            reasons.append(L("No problems detected.", "Aucune anomalie détectée."))
        }

        return HealthAssessment(status: status, healthPercent: lifeRemaining, reasons: reasons)
    }
}
