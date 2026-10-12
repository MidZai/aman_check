import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import CoreGraphics
import AmanCore
import AmanDesign
import DiskHealthCore

/// Ports et connecteurs validés automatiquement (correctifs §6.6) : aucun bouton « Valider ».
/// - USB / Thunderbolt : notifications IOKit sur `IOUSBHostDevice` ; le port est identifié en remontant
///   jusqu'au port du contrôleur XHCI (`UsbCPortNumber`, lu sur MacBookPro16,1 : 1 à 4).
/// - Charge : adaptateur secteur détecté (IOPowerSources), avec sa puissance.
/// - Vidéo : ajout d'un écran (CGDisplayRegisterReconfigurationCallback).
/// - Casque : sortie intégrée qui passe sur la prise casque (Core Audio).
/// - Carte SD : volume monté sur le lecteur SD.
@MainActor
final class PortsMonitor: ObservableObject {
    enum Item: String, CaseIterable, Identifiable {
        case charging, video, headphones, sdCard
        var id: String { rawValue }
    }

    enum ItemState: Equatable { case waiting, ok(String), skipped, notWorking }

    struct PortHit: Identifiable, Equatable {
        let id: String          // clé du port physique
        let label: String
        let device: String
        let speed: String?
    }

    @Published private(set) var ports: [PortHit] = []
    @Published var items: [Item: ItemState] = [:]
    @Published private(set) var lastEvent: String?
    @Published var portsSkipped = false
    @Published var portsNotWorking = false

    private var notifyPort: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var knownDevices: Set<UInt64> = []
    private var timer: Timer?
    private var wasOnAC: Bool?
    private var initialHeadphones = false
    private var mountObserver: NSObjectProtocol?
    fileprivate static weak var current: PortsMonitor?

    func start(profile: DeviceProfile) {
        PortsMonitor.current = self
        for item in Item.allCases where applies(item, profile) { items[item] = .waiting }
        startUSB()
        wasOnAC = Self.isOnAC()
        initialHeadphones = AudioDevices.defaultDevice(input: false)?.isHeadphones ?? false
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        CGDisplayRegisterReconfigurationCallback(displayCallback, nil)
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSDCard() }
        }
        DiagnosticLog.shared.log("ports", "surveillance démarrée · \(knownDevices.count) périphériques USB déjà présents · secteur=\(wasOnAC.map(String.init) ?? "?")")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        CGDisplayRemoveReconfigurationCallback(displayCallback, nil)
        if iterator != 0 { IOObjectRelease(iterator); iterator = 0 }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
        if let mountObserver { NSWorkspace.shared.notificationCenter.removeObserver(mountObserver) }
    }

    func applies(_ item: Item, _ profile: DeviceProfile) -> Bool {
        switch item {
        case .charging: return profile.hasBattery
        case .video: return true
        case .headphones: return profile.hasHeadphoneJack
        case .sdCard: return profile.hasSDSlot
        }
    }

    // MARK: USB

    private func startUSB() {
        let port = IONotificationPortCreate(kIOMainPortDefault)
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let callback: IOServiceMatchingCallback = { _, iterator in
            MainActor.assumeIsolated { PortsMonitor.current?.drain(iterator, initial: false) }
        }
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                                                      callback, nil, &iterator)
        guard result == KERN_SUCCESS else {
            DiagnosticLog.shared.log("ports", "notification USB impossible : \(result)")
            return
        }
        drain(iterator, initial: true)
    }

    fileprivate func drain(_ iterator: io_iterator_t, initial: Bool) {
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(device, &entryID)
            if initial {
                knownDevices.insert(entryID)
                continue
            }
            guard !knownDevices.contains(entryID) else { continue }
            knownDevices.insert(entryID)
            handleNewDevice(device)
        }
    }

    private func handleNewDevice(_ device: io_object_t) {
        let name = (IORegistryEntryCreateCFProperty(device, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String)
            ?? L("USB device", "Périphérique USB")
        let location = (IORegistryEntryCreateCFProperty(device, "locationID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.uint32Value
        let speed = (IORegistryEntryCreateCFProperty(device, "Device Speed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        let port = Self.rootPort(of: device)
        DiagnosticLog.shared.log("ports", "USB branché : \(name) locationID=\(location.map { String(format: "0x%08X", $0) } ?? "-") vitesse=\(speed.map(String.init) ?? "-") port=\(port.name) UsbCPortNumber=\(port.number.map(String.init) ?? "-")")
        lastEvent = name
        let key = port.number.map { "usbc-\($0)" } ?? "port-\(port.name)"
        guard !ports.contains(where: { $0.id == key }) else { return }
        let label = port.number.map { L("USB-C port no. \($0)", "Port USB-C n° \($0)") } ?? L("USB port", "Port USB")
        ports.append(PortHit(id: key, label: label, device: name, speed: speed.flatMap(Self.speedText)))
    }

    /// Remonte le registre jusqu'au port du contrôleur (« SSP1@00100000 », classe …XHCI…Port).
    /// TODO: à valider sur Apple Silicon (classes de contrôleur différentes).
    nonisolated static func rootPort(of device: io_object_t) -> (name: String, number: Int?) {
        var current = device
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current)
            current = parent
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &className)
            let cls = String(cString: className)
            if cls.contains("Port") && (cls.contains("XHCI") || cls.contains("USB")) {
                var nameBuffer = [CChar](repeating: 0, count: 128)
                IORegistryEntryGetName(current, &nameBuffer)
                let number = (IORegistryEntryCreateCFProperty(current, "UsbCPortNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
                return (String(cString: nameBuffer), number)
            }
        }
        return ("?", nil)
    }

    /// Valeurs de « Device Speed » d'IOUSBHostDevice. TODO: à valider pour 4 et plus.
    nonisolated static func speedText(_ speed: Int) -> String? {
        switch speed {
        case 0: return "1,5 Mb/s"
        case 1: return "12 Mb/s"
        case 2: return "480 Mb/s"
        case 3: return "5 Gb/s"
        case 4: return "10 Gb/s"
        default: return nil
        }
    }

    // MARK: Charge, casque, vidéo, SD

    /// Adaptateur secteur branché : IOPSCopyExternalPowerAdapterDetails renvoie nil sans adaptateur.
    nonisolated static func isOnAC() -> Bool? {
        IOPSCopyExternalPowerAdapterDetails() != nil
    }

    private func poll() {
        if items[.charging] == .waiting, let onAC = Self.isOnAC() {
            if onAC, wasOnAC == false {
                let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
                let watts = (details?["Watts"] as? NSNumber)?.intValue
                items[.charging] = .ok(watts.map { L("Charger detected · \($0) W", "Chargeur détecté · \($0) W") } ?? L("Charger detected", "Chargeur détecté"))
                DiagnosticLog.shared.log("ports", "chargeur branché · \(details ?? [:])")
            }
            wasOnAC = onAC
        }
        if items[.headphones] == .waiting, let output = AudioDevices.defaultDevice(input: false) {
            if output.isHeadphones && !initialHeadphones {
                items[.headphones] = .ok(L("Headphones detected", "Casque détecté"))
            }
            initialHeadphones = output.isHeadphones
        }
    }

    fileprivate func displayAdded(_ id: CGDirectDisplayID) {
        guard CGDisplayIsBuiltin(id) == 0, items[.video] == .waiting else { return }
        let name = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?.localizedName
        items[.video] = .ok(L("Display detected", "Écran détecté") + (name.map { " · \($0)" } ?? ""))
        DiagnosticLog.shared.log("ports", "écran ajouté : \(id) \(name ?? "")")
    }

    private func checkSDCard() {
        guard items[.sdCard] == .waiting else { return }
        // TODO: à valider sur un Mac avec lecteur SD (MacBook Pro 14/16 2021+).
        if DiskDiscovery.listPhysicalDisks().contains(where: { $0.protocolType == .sdCard }) {
            items[.sdCard] = .ok(L("Card detected", "Carte détectée"))
        }
    }
}

private func displayCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    guard flags.contains(.addFlag) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { PortsMonitor.current?.displayAdded(display) }
    }
}

struct PortsTestView: View {
    let profile: DeviceProfile
    let finish: (TestResult) -> Void
    @StateObject private var monitor = PortsMonitor()

    var body: some View {
        TestScaffold(title: L("Ports and connectors", "Ports et connecteurs"),
                     instruction: L("Plug a USB key or any USB device into each port, one after the other: each port turns green on its own. Every line is optional.",
                                    "Branchez une clé USB ou n'importe quel périphérique USB dans chaque port, l'un après l'autre : chaque port passe au vert tout seul. Chaque ligne est facultative.")) {
            VStack(alignment: .leading, spacing: 18) {
                portsCard
                ForEach(PortsMonitor.Item.allCases.filter { monitor.items[$0] != nil }) { item in
                    itemRow(item)
                }
            }
            .frame(maxWidth: 760)
        } actions: {
            Button(L("Finish", "Terminer")) { complete() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { monitor.start(profile: profile) }
        .onDisappear { monitor.stop() }
    }

    private var portsCard: some View {
        AmanCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(L("USB-C / Thunderbolt ports", "Ports USB-C / Thunderbolt"), systemImage: "cable.connector").font(.headline)
                    InfoButton(L("Any USB device works (key, mouse, phone cable…), with an adapter if needed. Each port is recognized by its position: plugging the same key into another port validates that port.",
                                 "N'importe quel périphérique USB convient (clé, souris, câble de téléphone…), avec un adaptateur si besoin. Chaque port est reconnu par sa position : la même clé branchée dans un autre port valide cet autre port."))
                    Spacer()
                    if let total = profile.thunderboltPorts {
                        Text(L("\(min(monitor.ports.count, total)) of \(total) tested", "\(min(monitor.ports.count, total)) sur \(total) testés"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("\(monitor.ports.count) tested", "\(monitor.ports.count) testé(s)")).foregroundStyle(.secondary)
                    }
                }
                if let total = profile.thunderboltPorts {
                    let slots = slotAssignment(total: total)
                    HStack(spacing: 14) {
                        ForEach(0..<total, id: \.self) { index in
                            let hit = slots[index]
                            VStack(spacing: 6) {
                                Capsule()
                                    .fill(hit == nil ? Color.secondary.opacity(0.18) : Color.green)
                                    .frame(width: 46, height: 16)
                                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35)))
                                Text(hit == nil ? L("Port \(index + 1)", "Port \(index + 1)") : L("OK", "OK"))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(hit == nil ? Color.secondary : Color.green)
                            }
                            .animation(.easeOut(duration: 0.2), value: hit)
                        }
                    }
                }
                ForEach(monitor.ports) { hit in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(hit.label + L(": ", " : ") + hit.device)
                        if let speed = hit.speed { Text(speed).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
                if monitor.ports.isEmpty {
                    Text(L("Waiting for a device…", "En attente d'un périphérique…")).foregroundStyle(.secondary).font(.callout)
                }
                HStack {
                    Toggle(L("I have no USB device", "Je n'ai pas de périphérique USB"), isOn: $monitor.portsSkipped)
                    Spacer()
                    Toggle(L("A port does not react", "Un port ne réagit pas"), isOn: $monitor.portsNotWorking)
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }
        }
    }

    /// Port n° N (UsbCPortNumber) allumé à sa place ; les ports sans numéro remplissent les cases libres.
    private func slotAssignment(total: Int) -> [PortsMonitor.PortHit?] {
        var slots = [PortsMonitor.PortHit?](repeating: nil, count: total)
        var unnumbered: [PortsMonitor.PortHit] = []
        for hit in monitor.ports {
            if hit.id.hasPrefix("usbc-"), let n = Int(hit.id.dropFirst(5)), (1...total).contains(n), slots[n - 1] == nil {
                slots[n - 1] = hit
            } else {
                unnumbered.append(hit)
            }
        }
        for hit in unnumbered {
            if let free = slots.firstIndex(where: { $0 == nil }) { slots[free] = hit }
        }
        return slots
    }

    private func itemRow(_ item: PortsMonitor.Item) -> some View {
        let state = monitor.items[item] ?? .waiting
        return HStack(spacing: 12) {
            Image(systemName: symbol(item))
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item)).font(.headline)
                Text(hint(item, state)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            InfoButton(help(item))
            switch state {
            case .ok:
                StatusPill(.good, text: L("Detected", "Détecté"))
            case .skipped:
                Button(L("Undo", "Annuler")) { monitor.items[item] = .waiting }
                StatusPill(.notTested)
            case .notWorking:
                Button(L("Undo", "Annuler")) { monitor.items[item] = .waiting }
                StatusPill(.problem, text: L("Does not react", "Ne réagit pas"))
            case .waiting:
                Menu(L("Not tested", "Pas testé")) {
                    Button(L("I don't have the cable", "Je n'ai pas le câble")) { monitor.items[item] = .skipped }
                    Button(L("I plugged it in, nothing happens", "Je l'ai branché, rien ne se passe")) { monitor.items[item] = .notWorking }
                }
                .fixedSize()
            }
        }
        .padding(12)
        .background(AmanDesign.cardBackground, in: RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AmanDesign.cardRadius, style: .continuous).strokeBorder(AmanDesign.cardBorder))
    }

    private func title(_ item: PortsMonitor.Item) -> String {
        switch item {
        case .charging: return profile.hasMagSafe ? L("Charging (MagSafe or USB-C)", "Charge (MagSafe ou USB-C)") : L("Charging", "Charge")
        case .video: return profile.hasHDMI ? L("Video output (HDMI or USB-C)", "Sortie vidéo (HDMI ou USB-C)") : L("Video output", "Sortie vidéo")
        case .headphones: return L("Headphone jack", "Prise casque")
        case .sdCard: return L("SD card reader", "Lecteur de carte SD")
        }
    }

    private func hint(_ item: PortsMonitor.Item, _ state: PortsMonitor.ItemState) -> String {
        if case .ok(let detail) = state { return detail }
        switch item {
        case .charging: return L("Unplug the charger, then plug it back in.", "Débranchez le chargeur, puis rebranchez-le.")
        case .video: return L("Connect an external display.", "Branchez un écran externe.")
        case .headphones: return L("Plug in wired headphones.", "Branchez un casque filaire.")
        case .sdCard: return L("Insert an SD card.", "Insérez une carte SD.")
        }
    }

    private func help(_ item: PortsMonitor.Item) -> String {
        switch item {
        case .charging:
            return L("Detected when the power adapter is connected. The power shown is the one announced by the adapter. Not having the charger is not a defect: mark it “not tested”.",
                     "Détecté au branchement de l'adaptateur secteur. La puissance affichée est celle annoncée par l'adaptateur. Ne pas avoir le chargeur n'est pas un défaut : notez-le « pas testé ».")
        case .video:
            return L("Detected as soon as macOS sees a new display (USB-C, Thunderbolt or HDMI adapter).",
                     "Détecté dès que macOS voit un nouvel écran (USB-C, Thunderbolt ou adaptateur HDMI).")
        case .headphones:
            return L("Detected when the sound output switches to the headphone jack. Bluetooth or USB headphones do not count.",
                     "Détecté quand la sortie son passe sur la prise casque. Un casque Bluetooth ou USB ne compte pas.")
        case .sdCard:
            return L("Detected when a card is mounted. The card must be readable by macOS.",
                     "Détecté au montage d'une carte. La carte doit être lisible par macOS.")
        }
    }

    private func symbol(_ item: PortsMonitor.Item) -> String {
        switch item {
        case .charging: return "bolt.fill"
        case .video: return "display.2"
        case .headphones: return "headphones"
        case .sdCard: return "sdcard"
        }
    }

    private func complete() {
        monitor.stop()
        var tested: [String] = monitor.ports.map { "\($0.label) (\($0.device))" }
        var notWorking: [String] = []
        var untested: [String] = []
        for (item, state) in monitor.items {
            switch state {
            case .ok(let detail): tested.append(title(item) + L(": ", " : ") + detail)
            case .notWorking: notWorking.append(title(item))
            case .skipped, .waiting: untested.append(title(item))
            }
        }
        if monitor.portsNotWorking { notWorking.append(L("A USB-C port", "Un port USB-C")) }
        if let total = profile.thunderboltPorts, monitor.ports.count < total, !monitor.portsNotWorking {
            let missing = total - monitor.ports.count
            // Case « Je n'ai pas de périphérique USB » : la raison figure dans le rapport, le verdict reste le même
            // (un port non testé n'est pas défectueux).
            untested.append(monitor.portsSkipped
                            ? L("\(missing) USB-C port(s) (no device available)", "\(missing) port(s) USB-C (aucun périphérique disponible)")
                            : L("\(missing) USB-C port(s)", "\(missing) port(s) USB-C"))
        }

        let portsText: String = {
            if let total = profile.thunderboltPorts {
                return L("\(min(monitor.ports.count, total)) of \(total) USB-C ports tested", "\(min(monitor.ports.count, total)) ports USB-C sur \(total) testés")
            }
            return L("\(monitor.ports.count) port(s) tested", "\(monitor.ports.count) port(s) testé(s)")
        }()
        let okItems = monitor.items.values.filter { if case .ok = $0 { return true } else { return false } }.count
        let summary = portsText + (okItems > 0 ? " · " + L("\(okItems) other connector(s)", "\(okItems) autre(s) connecteur(s)") : "")
        var details = tested
        if !untested.isEmpty { details.append(L("Not tested: ", "Non testés : ") + untested.joined(separator: ", ")) }
        if !notWorking.isEmpty { details.append(L("Does not react: ", "Ne réagit pas : ") + notWorking.joined(separator: ", ")) }

        if !notWorking.isEmpty {
            finish(TestResult(test: .ports, outcome: .failed, provenance: .userObserved, summary: summary, details: details))
        } else if tested.isEmpty {
            finish(.notTested(.ports, reason: monitor.portsSkipped
                              ? L("No USB device available", "Aucun périphérique USB disponible")
                              : L("No connector tested", "Aucun connecteur testé")))
        } else {
            // Un connecteur non testé n'est pas défectueux : il figure dans les détails, pas dans le verdict.
            finish(TestResult(test: .ports, outcome: .passed, provenance: .measuredAuto, summary: summary, details: details))
        }
    }
}
