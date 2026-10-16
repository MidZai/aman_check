import Testing
import Foundation
@testable import AmanCore
import DiskHealthCore

@Suite("Performance")
struct PerformanceAnalysisTests {
    private func find(_ list: [Measurement], _ id: String) -> Measurement? { list.first { $0.id == id } }
    private let empty = PerformanceReference(entries: [:])

    @Test("Stabilité : 3 premières tranches contre 3 dernières, seuils 10 % et 25 %")
    func stability() {
        #expect(PerformanceAnalysis.drop([100, 100, 100, 100, 100, 100]) == 0)
        #expect(PerformanceAnalysis.drop([100, 100, 100, 95, 92, 92, 91]).map { ($0 * 100).rounded() } == 8)
        #expect(PerformanceAnalysis.drop([100, 100, 100, 50, 50, 50]) == 0.5)
        // Une hausse n'est pas une baisse négative.
        #expect(PerformanceAnalysis.drop([80, 80, 80, 100, 100, 100]) == 0)
        // Trop peu de tranches : pas de conclusion.
        #expect(PerformanceAnalysis.drop([100, 90, 80, 70, 60]) == nil)
        #expect(PerformanceAnalysis.status(forDrop: 0.09) == .good)
        #expect(PerformanceAnalysis.status(forDrop: 0.10) == .watch)
        #expect(PerformanceAnalysis.status(forDrop: 0.25) == .watch)
        #expect(PerformanceAnalysis.status(forDrop: 0.26) == .problem)
    }

    @Test("Forte baisse sous charge : problème, avec le texte sur la ventilation")
    func throttling() {
        let run = PerformanceRun(cpuSlices: [200, 200, 200, 190, 120, 110, 100], gpuSlices: nil, memoryGBps: nil, duration: 30)
        let m = PerformanceAnalysis.measurements(run, reference: empty, expectsFan: true)
        let stability = find(m, MetricID.performanceStability)
        #expect(stability?.status == .problem)
        #expect(stability?.provenance == .derived)
        #expect(stability?.note == L("Performance drops sharply under load. Check the cooling.", "Les performances baissent fortement sous charge. Vérifiez la ventilation."))
        // La pire des deux baisses compte : GPU stable, processeur en chute.
        let both = PerformanceRun(cpuSlices: [200, 200, 200, 120, 110, 100], gpuSlices: Array(repeating: 1000, count: 10), memoryGBps: nil, duration: 50)
        #expect(find(PerformanceAnalysis.measurements(both, reference: empty, expectsFan: true), MetricID.performanceStability)?.status == .problem)
    }

    @Test("Puce inconnue : valeur brute, « Pas encore de référence », sans jugement")
    func unknownChip() {
        let run = PerformanceRun(cpuSlices: Array(repeating: 142, count: 15), gpuSlices: Array(repeating: 4000, count: 10), memoryGBps: 20,
                                 duration: 56, chip: "Apple M9 Ultra")
        let m = PerformanceAnalysis.measurements(run, reference: empty, expectsFan: true)
        let cpu = find(m, MetricID.performanceCPU)
        #expect(cpu?.status == .info)
        #expect(cpu?.value == .double(142))
        #expect(cpu?.detail == L("No reference for this model yet.", "Pas encore de référence pour ce modèle."))
        #expect(find(m, MetricID.performanceGPU)?.status == .info)
        #expect(find(m, MetricID.performanceStability)?.status == .good)
    }

    @Test("Référence : sous 80 % à surveiller, jamais problème ; au-dessus, bon")
    func reference() {
        let table = PerformanceReference(entries: ["Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz": .init(cpuGflops: 140, gpuGflops: 4000, source: "test")])
        let slow = PerformanceRun(cpuSlices: Array(repeating: 70, count: 15), gpuSlices: Array(repeating: 3900, count: 10), memoryGBps: nil,
                                  duration: 50, chip: "Intel(R) Core(TM)  i9-9980HK CPU @ 2.40GHz ")
        let m = PerformanceAnalysis.measurements(slow, reference: table, expectsFan: true)
        #expect(find(m, MetricID.performanceCPU)?.status == .watch)
        #expect(find(m, MetricID.performanceGPU)?.status == .good)
        #expect(!m.contains { $0.status == .problem })
    }

    @Test("Table de référence : JSON lu, JSON vide ou illisible → aucune référence")
    func referenceJSON() {
        let json = #"{ "Apple M1": { "cpu_gflops": 100.5, "gpu_gflops": 2000, "source": "MacBookAir10,1" } }"#
        let table = PerformanceReference(json: Data(json.utf8))
        #expect(table.entry(for: "apple m1")?.cpuGflops == 100.5)
        #expect(table.entry(for: "Apple M2") == nil)
        #expect(table.entry(for: nil) == nil)
        #expect(PerformanceReference(json: Data("{}".utf8)).entries.isEmpty)
        #expect(PerformanceReference(json: Data("pas du json".utf8)).entries.isEmpty)
        #expect(PerformanceReference(json: nil).entries.isEmpty)
    }

    @Test("La table livrée se lit, et ne contient que des mesures réelles sourcées")
    func shippedTable() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AmanCheck/Performance/PerformanceReference.json")
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: PerformanceReferenceEntry].self, from: data)
        for (chip, entry) in decoded {
            #expect(entry.source?.isEmpty == false, "\(chip) : référence sans source")
        }
    }

    @Test("Ventilateurs restés arrêtés : problème seulement si le processeur a chauffé")
    func fansUnderLoad() {
        func fans(_ speeds: [Double?], temps: [Double?], expects: Bool?) -> Measurement? {
            let run = PerformanceRun(cpuSlices: Array(repeating: 100, count: 6), gpuSlices: nil, memoryGBps: nil,
                                     temperatures: temps, fanSpeeds: speeds, duration: 30)
            return find(PerformanceAnalysis.measurements(run, reference: empty, expectsFan: expects), MetricID.performanceFans)
        }
        #expect(fans([0, 0, 0], temps: [60, 85, 95], expects: true)?.status == .problem)
        #expect(fans([0, 0, 0], temps: [50, 60, 70], expects: true)?.status == .info)
        #expect(fans([1800, 3000, 5600], temps: [60, 85, 95], expects: true)?.value == .int(5600))
        #expect(fans([1800, 3000, 5600], temps: [60, 85, 95], expects: true)?.status == .info)
        // Mac sans ventilateur : pas de ligne ; lecture impossible : non disponible.
        #expect(fans([], temps: [95], expects: false) == nil)
        #expect(fans([nil, nil], temps: [95], expects: true)?.status == .unavailable)
    }

    @Test("Non lancé ou annulé : une ligne « Non testé »")
    func notRun() {
        let m = PerformanceAnalysis.notRun()
        #expect(m.count == 1)
        #expect(m.first?.status == .notTested)
        #expect(PerformanceAnalysis.notRun(cancelled: true).first?.note == L("Test cancelled before the end.", "Test annulé avant la fin."))
        // Compté « non testé » dans les compteurs.
        let profile = DeviceProfile.make(modelIdentifier: "Macmini9,1", simulated: true)
        let report = ConditionReport(appVersion: "t", profile: profile, measurements: m, tests: [], plannedTests: [])
        #expect(ReportSummary(report: report).notTested == 1)
    }

    @Test("Conditions : sur batterie, le rapport le dit")
    func battery() {
        let run = PerformanceRun(cpuSlices: Array(repeating: 100, count: 6), gpuSlices: nil, memoryGBps: nil, duration: 55,
                                 powerAtStart: .battery, powerAtEnd: .battery)
        let conditions = find(PerformanceAnalysis.measurements(run, reference: empty, expectsFan: true), MetricID.performanceConditions)
        #expect(conditions?.note != nil)
    }
}
