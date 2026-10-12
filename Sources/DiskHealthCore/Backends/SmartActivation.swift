import Foundation

/// Access to an ATA drive for turning on S.M.A.R.T. (faked in the tests).
public protocol ATASmartDevice {
    func read(bsdName: String) throws -> DiskHealthSnapshot
    /// Serial number read from Identify, available even when S.M.A.R.T. is disabled.
    func serialNumber(bsdName: String) -> String?
    func enableSmart(bsdName: String) throws
}

public struct IOKitATADevice: ATASmartDevice {
    public init() {}

    public func read(bsdName: String) throws -> DiskHealthSnapshot {
        try ATABackend.read(bsdName: bsdName)
    }

    public func serialNumber(bsdName: String) -> String? {
        guard let identify = try? ATAReader.readIdentify(bsdName: bsdName) else { return nil }
        let serial = ATASmartParser.parseString(data: identify, range: 20..<40)
        return serial.isEmpty ? nil : serial
    }

    public func enableSmart(bsdName: String) throws {
        try ATAReader.enableSmart(bsdName: bsdName)
    }
}

/// Drives for which Aman already tried to turn S.M.A.R.T. on, by serial number, with the result
/// (0: success, otherwise the error code). Survives relaunches: a single automatic attempt.
public protocol SmartActivationMemory: AnyObject {
    func attempt(for serial: String) -> Int32?
    func record(_ code: Int32, for serial: String)
}

public final class UserDefaultsActivationMemory: SmartActivationMemory, @unchecked Sendable {
    public static let defaultsKey = "smartActivationAttempts"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func attempt(for serial: String) -> Int32? {
        lock.lock(); defer { lock.unlock() }
        let attempts = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
        return attempts[serial].map { Int32(truncatingIfNeeded: $0) }
    }

    public func record(_ code: Int32, for serial: String) {
        lock.lock(); defer { lock.unlock() }
        var attempts = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
        attempts[serial] = Int(code)
        defaults.set(attempts, forKey: Self.defaultsKey)
    }
}

public enum SmartActivationResult: Equatable {
    /// S.M.A.R.T. was already on.
    case read(DiskHealthSnapshot)
    /// Aman just turned it on, then read the drive again.
    case enabled(DiskHealthSnapshot)
    /// Disabled, no attempt: setting off, or activation already succeeded once
    /// (someone turned it off since; it isn't turned on again without asking).
    case disabled
    /// Activation refused by the drive or the driver, now or during a previous launch.
    case enableFailed(code: Int32)
}

/// Reads an ATA drive and turns S.M.A.R.T. on if it's disabled:
/// a single automatic attempt per drive, never another attempt without the user.
public struct SmartActivator {
    private let device: ATASmartDevice
    private let memory: SmartActivationMemory

    public init(device: ATASmartDevice = IOKitATADevice(), memory: SmartActivationMemory) {
        self.device = device
        self.memory = memory
    }

    public func read(bsdName: String, autoEnable: Bool) throws -> SmartActivationResult {
        do {
            return .read(try device.read(bsdName: bsdName))
        } catch ATAReadError.smartDisabled {
            let serial = memoryKey(bsdName: bsdName)
            if let previous = memory.attempt(for: serial) {
                return previous == 0 ? .disabled : .enableFailed(code: previous)
            }
            guard autoEnable else { return .disabled }
            return try enable(bsdName: bsdName, serial: serial)
        }
    }

    /// Activation requested by the user (“Turn On” or “Try Again” button).
    public func enable(bsdName: String) throws -> SmartActivationResult {
        try enable(bsdName: bsdName, serial: memoryKey(bsdName: bsdName))
    }

    private func enable(bsdName: String, serial: String) throws -> SmartActivationResult {
        do {
            try device.enableSmart(bsdName: bsdName)
        } catch {
            let code = Self.code(of: error)
            memory.record(code, for: serial)
            return .enableFailed(code: code)
        }
        memory.record(0, for: serial)
        return .enabled(try device.read(bsdName: bsdName))
    }

    /// Without a readable serial number, the BSD name is used as a fallback.
    private func memoryKey(bsdName: String) -> String {
        if let s = device.serialNumber(bsdName: bsdName)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return DiskIdentity.key(model: "smartActivation", serial: s)
        }
        return "bsd:\(bsdName)"
    }

    static func code(of error: Error) -> Int32 {
        switch error as? ATAReadError {
        case .invalidArguments: return -1
        case .diskNotFound: return -2
        case .mediaNotFound: return -3
        case .smartServiceNotFound: return -4
        case .pluginCreationFailed: return -5
        case .smartDisabled: return -6
        case .ioError(let code), .unknown(let code): return code
        case .parseFailed, nil: return -7
        }
    }
}
