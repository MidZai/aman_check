import SwiftUI
import IOKit.hid
import AmanCore
import AmanDesign
import DiskHealthCore

/// Claviers, souris et trackpads connectés (énumération HID, sans autorisation « Surveillance de l'entrée »).
enum HIDInventory {
    static func devices() -> [HIDDeviceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.map { device in
            func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
            let usage = (property(kIOHIDPrimaryUsageKey) as? NSNumber)?.intValue ?? 0
            return HIDDeviceInfo(name: property(kIOHIDProductKey) as? String ?? L("Input device", "Périphérique d'entrée"),
                                 kind: usage == kHIDUsage_GD_Keyboard ? .keyboard : .pointer,
                                 isBuiltIn: (property("Built-In") as? NSNumber)?.boolValue ?? false,
                                 transport: property(kIOHIDTransportKey) as? String ?? "")
        }
    }
}

/// Surveille les périphériques externes pendant un test du clavier ou du trackpad (vérification chaque seconde).
@MainActor
final class ExternalInputMonitor: ObservableObject {
    let test: TestID
    @Published private(set) var blockers: [String] = []
    private var timer: Timer?

    init(test: TestID) {
        self.test = test
        refresh()
    }

    var isBlocked: Bool { !blockers.isEmpty }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let found = ExternalInputGuard.blockers(for: test, devices: HIDInventory.devices())
        if found != blockers {
            DiagnosticLog.shared.log(test.rawValue, "périphériques externes : \(found.isEmpty ? "aucun" : found.joined(separator: ", "))")
            blockers = found
        }
    }
}

/// Écran affiché à la place du test tant qu'un périphérique externe est branché.
struct ExternalInputBlockedView: View {
    let test: TestID
    let blockers: [String]
    let finish: (TestResult) -> Void

    var body: some View {
        TestScaffold(title: test.title, instruction: ExternalInputGuard.message(for: test, blockers: blockers)) {
            VStack(spacing: 14) {
                Image(systemName: test == .keyboard ? "keyboard.badge.exclamationmark" : "computermouse")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(L("Waiting for the device to be unplugged…", "En attente du débranchement…"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } actions: {
            Button(L("Don't Test Now", "Ne pas tester maintenant")) {
                finish(.notTested(test, reason: test == .keyboard
                                  ? L("External keyboard connected", "Clavier externe branché")
                                  : L("External mouse or trackpad connected", "Souris ou trackpad externe branché")))
            }
        }
    }
}
