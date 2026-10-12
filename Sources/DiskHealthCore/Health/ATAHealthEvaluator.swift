import Foundation

public enum ATAHealthEvaluator {
    public static func evaluate(snapshot: ATASmartSnapshot) -> HealthAssessment {
        // No attribute, or a block that failed its checksum: nothing can be assessed.
        if snapshot.attributes.isEmpty || !snapshot.checksumValid {
            return HealthAssessment(status: .unknown, healthPercent: nil, reasons: [HealthEngine.unverifiedDataReason])
        }
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
        // Only a pre-fail attribute (bit 0 of the flags) below its threshold means an imminent failure.
        // Temperature attributes never count: their threshold is a comfort limit, not a failure limit.
        for attr in snapshot.attributes {
            let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
            guard attr.isPreFail, info.role != .temperature, attr.isBelowThreshold else { continue }
            status = .bad
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
            case .temperature:
                break
            default:
                if attr.isBelowThreshold {
                    // An old-age attribute below its threshold is worth watching, not a failure (see above).
                    if !attr.isPreFail {
                        cautionReasons.append(L("The “\(info.name)” attribute has dropped below its threshold.", "L'attribut « \(info.name) » est passé sous son seuil."))
                    }
                } else if attr.hasCrossedThreshold {
                    // Threshold crossed in the past, but not anymore (otherwise it's already handled above).
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
            // The thresholds block failed its checksum: the problems found above stand, but “good”
            // would rest on thresholds we couldn't verify.
            if !snapshot.thresholdsChecksumValid {
                return HealthAssessment(status: .unknown, healthPercent: lifeRemaining, reasons: [HealthEngine.unverifiedThresholdsReason])
            }
            reasons.append(L("No problems detected.", "Aucune anomalie détectée."))
        }

        return HealthAssessment(status: status, healthPercent: lifeRemaining, reasons: reasons)
    }
}
