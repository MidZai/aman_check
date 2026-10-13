import Foundation

/// Fait tourner un travail bloquant (commandes, IOKit) sur une file en arrière-plan et en attend le résultat.
/// Les collecteurs ont un cœur synchrone (Aman Legacy, macOS 10.13, sans concurrence Swift) ;
/// Aman Check les appelle par leur version `async`, construite avec ceci.
@available(macOS 10.15, *)
public func runInBackground<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}
