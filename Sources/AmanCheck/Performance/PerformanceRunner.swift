import Foundation
import Accelerate
import Metal
import IOKit.ps
import AmanCore
import DiskHealthCore

/// Test de performance (spec §7.8) : processeur 30 s, GPU 20 s, mémoire 5 s, relevés de température et de
/// ventilateurs toutes les 2 s. Lancé uniquement par la personne ; annulable à tout moment (→ « Non testé »).
@MainActor
final class PerformanceRunner: ObservableObject {
    enum Stage: Equatable {
        case cpu, gpu, memory

        var title: String {
            switch self {
            case .cpu: return L("Processor", "Processeur")
            case .gpu: return L("Graphics (GPU)", "Graphisme (GPU)")
            case .memory: return L("Memory", "Mémoire")
            }
        }
    }

    enum State: Equatable {
        case idle
        case running(Stage)
        case finished
        case cancelled
    }

    @Published private(set) var state: State = .idle
    /// 0…1 sur la durée totale prévue.
    @Published private(set) var progress = 0.0
    /// Dernière tranche mesurée (GFLOPS ou Go/s), pour l'affichage en direct.
    @Published private(set) var lastValue: String?
    @Published private(set) var temperature: Double?
    @Published private(set) var fanSpeed: Double?
    @Published private(set) var run: PerformanceRun?

    private let cancelFlag = CancelFlag()
    private var startedAt = Date()

    static var totalSeconds: Double { PerformanceAnalysis.cpuSeconds + PerformanceAnalysis.gpuSeconds + PerformanceAnalysis.memorySeconds }

    var isRunning: Bool { if case .running = state { return true } else { return false } }

    func start(completion: @escaping (PerformanceRun?) -> Void) {
        guard !isRunning else { return }
        cancelFlag.reset()
        state = .running(.cpu)
        progress = 0
        lastValue = nil
        run = nil
        startedAt = Date()
        let flag = cancelFlag
        DiagnosticLog.shared.log("performance", "début")
        Thread.detachNewThread { [weak self] in
            let result = Self.measure(flag: flag) { event in
                DispatchQueue.main.async { self?.apply(event) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.run = result
                    self.state = .finished
                    self.progress = 1
                    DiagnosticLog.shared.log("performance", "fin : cpu=\(result.cpuSlices) gpu=\(result.gpuSlices ?? []) mem=\(result.memoryGBps ?? 0) temp=\(result.temperatures) fans=\(result.fanSpeeds)")
                } else {
                    self.state = .cancelled
                    DiagnosticLog.shared.log("performance", "annulé")
                }
                completion(result)
            }
        }
    }

    func cancel() {
        cancelFlag.cancel()
    }

    // MARK: Événements du fil de mesure

    private enum Event {
        case stage(Stage)
        case slice(String)
        case sample(temperature: Double?, fan: Double?)
        case elapsed(Double)
    }

    private func apply(_ event: Event) {
        switch event {
        case .stage(let stage): if isRunning { state = .running(stage) }
        case .slice(let text): lastValue = text
        case .sample(let t, let f): temperature = t; fanSpeed = f
        case .elapsed(let seconds): progress = min(1, seconds / Self.totalSeconds)
        }
    }

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.lock(); value = true; lock.unlock() }
        func reset() { lock.lock(); value = false; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: Mesure (hors fil principal)

    private nonisolated static func measure(flag: CancelFlag, report: @escaping (Event) -> Void) -> PerformanceRun? {
        let began = Date()
        let session = SensorCollector.Session()
        var temperatures: [Double?] = []
        var fans: [Double?] = []
        func sample() {
            let t = session?.cpuTemperature()
            let f = session?.fastestFan()
            temperatures.append(t)
            fans.append(f)
            report(.sample(temperature: t, fan: f))
            report(.elapsed(Date().timeIntervalSince(began)))
        }
        let powerAtStart = powerSource()
        sample()

        // Processeur : multiplication de matrices 1024 × 1024 en double précision ; Accelerate répartit le
        // calcul sur tous les cœurs.
        report(.stage(.cpu))
        let cpu = cpuSlices(seconds: PerformanceAnalysis.cpuSeconds, flag: flag) { gflops in
            report(.slice("\(Formatters.integer(Int(gflops.rounded())))\(Formatters.unitSpace)GFLOPS"))
            sample()
        }
        guard !flag.isCancelled else { return nil }

        report(.stage(.gpu))
        let gpu = gpuSlices(seconds: PerformanceAnalysis.gpuSeconds, flag: flag) { gflops in
            report(.slice("\(Formatters.integer(Int(gflops.rounded())))\(Formatters.unitSpace)GFLOPS"))
            sample()
        }
        guard !flag.isCancelled else { return nil }

        report(.stage(.memory))
        let memory = memoryCopy(seconds: PerformanceAnalysis.memorySeconds, flag: flag)
        guard !flag.isCancelled else { return nil }
        sample()

        return PerformanceRun(cpuSlices: cpu, gpuSlices: gpu, memoryGBps: memory, temperatures: temperatures, fanSpeeds: fans,
                              duration: Date().timeIntervalSince(began), powerAtStart: powerAtStart, powerAtEnd: powerSource(),
                              chip: SystemReader.sysctlString("machdep.cpu.brand_string"))
    }

    private nonisolated static func cpuSlices(seconds: Double, flag: CancelFlag, onSlice: (Double) -> Void) -> [Double] {
        let n = 1024
        var a = [Double](repeating: 0, count: n * n)
        var b = [Double](repeating: 0, count: n * n)
        var c = [Double](repeating: 0, count: n * n)
        for i in 0..<(n * n) {
            a[i] = Double(i % 97) / 97
            b[i] = Double(i % 89) / 89
        }
        let flopsPerCall = 2.0 * Double(n) * Double(n) * Double(n)
        var slices: [Double] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !flag.isCancelled {
            let sliceStart = Date()
            var calls = 0
            while Date().timeIntervalSince(sliceStart) < PerformanceAnalysis.sliceSeconds, !flag.isCancelled {
                cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(n), Int32(n), Int32(n),
                            1.0, a, Int32(n), b, Int32(n), 0.0, &c, Int32(n))
                calls += 1
            }
            let elapsed = Date().timeIntervalSince(sliceStart)
            guard !flag.isCancelled, elapsed > 0 else { break }
            let gflops = Double(calls) * flopsPerCall / elapsed / 1e9
            slices.append(gflops)
            onSlice(gflops)
        }
        return slices
    }

    private nonisolated static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void aman_fma(device float4 *data [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        float4 x = data[id];
        const float4 m = float4(0.999999f);
        const float4 k = float4(0.000001f);
        for (int i = 0; i < 1024; i++) {
            x = fma(x, m, k);
            x = fma(x, m, k);
        }
        data[id] = x;
    }
    """

    /// `nil` : Metal indisponible (machine virtuelle, pilote absent).
    private nonisolated static func gpuSlices(seconds: Double, flag: CancelFlag, onSlice: (Double) -> Void) -> [Double]? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: kernelSource, options: nil),
              let function = library.makeFunction(name: "aman_fma"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        let threadsPerGroup = min(256, pipeline.maxTotalThreadsPerThreadgroup)
        let groups = (1 << 20) / threadsPerGroup
        let threads = groups * threadsPerGroup
        guard let buffer = device.makeBuffer(length: threads * MemoryLayout<SIMD4<Float>>.stride, options: .storageModePrivate) else { return nil }
        // 1 024 itérations × 2 FMA × 4 voies × 2 opérations.
        let flopsPerDispatch = Double(threads) * 1024 * 2 * 4 * 2
        let dispatchesPerBuffer = 4
        var slices: [Double] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !flag.isCancelled {
            let sliceStart = Date()
            var dispatches = 0
            while Date().timeIntervalSince(sliceStart) < PerformanceAnalysis.sliceSeconds, !flag.isCancelled {
                guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else { return slices.isEmpty ? nil : slices }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                for _ in 0..<dispatchesPerBuffer {
                    encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                                 threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1))
                }
                encoder.endEncoding()
                commands.commit()
                commands.waitUntilCompleted()
                if commands.status == .error { return slices.isEmpty ? nil : slices }
                dispatches += dispatchesPerBuffer
            }
            let elapsed = Date().timeIntervalSince(sliceStart)
            guard !flag.isCancelled, elapsed > 0 else { break }
            let gflops = Double(dispatches) * flopsPerDispatch / elapsed / 1e9
            slices.append(gflops)
            onSlice(gflops)
        }
        return slices
    }

    /// Copie séquentielle de blocs de 256 Mo ; Go/s copiés (lecture + écriture comptées une fois).
    /// Par morceaux de 1 Mo, destination décalée de 64 octets : sur des blocs entiers alignés sur les pages,
    /// `memcpy` de macOS remappe les pages au lieu de copier (mesuré : 4,9 millions de Go/s).
    private nonisolated static func memoryCopy(seconds: Double, flag: CancelFlag) -> Double? {
        let size = 256 << 20
        let chunk = 1 << 20
        let offset = 64
        guard let source = malloc(size), let destination = malloc(size + offset) else { return nil }
        defer { free(source); free(destination) }
        memset(source, 1, size)
        memset(destination, 0, size + offset)
        // memmove appelé par son adresse : le compilateur ne peut pas supprimer des copies dont la destination
        // n'est jamais relue (mesuré sans cela : plus de 500 000 Go/s).
        typealias Move = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int) -> UnsafeMutableRawPointer?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "memmove") else { return nil }   // RTLD_DEFAULT
        let move = unsafeBitCast(symbol, to: Move.self)
        var copied = 0.0
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, !flag.isCancelled {
            for position in stride(from: 0, to: size, by: chunk) {
                _ = move(destination + offset + position, source + position, chunk)
            }
            copied += Double(size)
        }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0, copied > 0 else { return nil }
        return copied / elapsed / 1e9
    }

    nonisolated static func powerSource() -> PowerSource {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return .unknown }
        switch type {
        case kIOPMACPowerKey: return .adapter
        case kIOPMBatteryPowerKey: return .battery
        default: return .unknown
        }
    }
}
