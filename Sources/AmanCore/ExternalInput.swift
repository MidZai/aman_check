import Foundation
import DiskHealthCore

/// Périphérique d'entrée vu par IOKit HID (clavier, souris, trackpad), réduit à ce qui sert au contrôle.
public struct HIDDeviceInfo: Sendable, Equatable {
    public enum Kind: Sendable { case keyboard, pointer }

    public let name: String
    public let kind: Kind
    /// Propriété `Built-In` : clavier et trackpad intégrés du MacBook.
    public let isBuiltIn: Bool
    /// `kIOHIDTransportKey` (« USB », « Bluetooth », « Virtual »…).
    public let transport: String

    public init(name: String, kind: Kind, isBuiltIn: Bool, transport: String) {
        self.name = name
        self.kind = kind
        self.isBuiltIn = isBuiltIn
        self.transport = transport
    }

    /// Branché de l'extérieur : ni intégré, ni virtuel (la Touch Bar se déclare comme clavier virtuel).
    public var isExternal: Bool { !isBuiltIn && transport != "Virtual" }
}

/// Un test du clavier ou du trackpad validé avec un périphérique externe ne prouverait rien
/// (cahier des charges niveau 2, §8 et §11) : le test refuse de démarrer tant qu'il en reste un.
public enum ExternalInputGuard {
    /// Noms des périphériques à débrancher avant de lancer `test`. Vide : le test peut démarrer.
    public static func blockers(for test: TestID, devices: [HIDDeviceInfo]) -> [String] {
        externalDevices(for: test, devices: devices)
    }

    /// Noms des périphériques externes du type testé (clavier ; souris et trackpads), sans doublon.
    /// Sur un Mac de bureau, ce sont les accessoires testés.
    public static func externalDevices(for test: TestID, devices: [HIDDeviceInfo]) -> [String] {
        let kind: HIDDeviceInfo.Kind
        switch test {
        case .keyboard: kind = .keyboard
        case .trackpad: kind = .pointer
        default: return []
        }
        var names: [String] = []
        for device in devices where device.kind == kind && device.isExternal && !names.contains(device.name) {
            names.append(device.name)
        }
        return names
    }

    /// Consigne affichée tant que le test est bloqué.
    public static func message(for test: TestID, blockers: [String]) -> String {
        let list = blockers.joined(separator: ", ")
        switch test {
        case .keyboard:
            return L("An external keyboard is connected (\(list)). Unplug it or turn it off: the test starts on its own once it is gone, because the app cannot tell the two keyboards apart.",
                     "Un clavier externe est branché (\(list)). Débranchez-le ou éteignez-le : le test démarre tout seul ensuite, car l'app ne peut pas distinguer les deux claviers.")
        default:
            return L("An external mouse or trackpad is connected (\(list)). Unplug it or turn it off: the test starts on its own once it is gone, because the app cannot tell it apart from the Mac's trackpad.",
                     "Une souris ou un trackpad externe est branché (\(list)). Débranchez-le ou éteignez-le : le test démarre tout seul ensuite, car l'app ne peut pas le distinguer du trackpad du Mac.")
        }
    }
}
