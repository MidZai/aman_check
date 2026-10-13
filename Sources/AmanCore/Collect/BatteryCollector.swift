import Foundation

/// Batterie (spec §6.2) : lecture IOKit + état déclaré par macOS, analyse dans AmanCore.
public enum BatteryCollector {
    @available(macOS 10.15, *)
    public static func collect(profile: DeviceProfile) async -> [Measurement] {
        await runInBackground { collectSync(profile: profile) }
    }

    /// Version synchrone (Aman Legacy) : lance `system_profiler`, à appeler hors du fil principal.
    public static func collectSync(profile: DeviceProfile) -> [Measurement] {
        // Profil simulé de Mac de bureau : pas de batterie, même si la machine de développement en a une.
        if profile.isSimulated && !profile.hasBattery { return [] }
        guard let props = SystemReader.batteryProperties() else { return [] }
        let registry = BatteryRegistry(properties: props)
        DiagnosticLog.shared.record("AppleSmartBattery", String(describing: registry))
        let sp = Shell.runSync("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"])
        if let sp { DiagnosticLog.shared.record("SPPowerDataType", sp.stdout) }
        let power = sp.flatMap { PowerProfile(systemProfilerJSON: Data($0.stdout.utf8)) }
        return BatteryAnalysis.analyze(registry: registry, power: power, ratedCyclesFromModel: profile.model?.ratedBatteryCycles)
    }
}
