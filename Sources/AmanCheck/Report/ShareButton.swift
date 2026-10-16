import SwiftUI
import AppKit

/// Bouton « Partager… » : feuille de partage native de macOS (`NSSharingServicePicker`), ancrée sur le bouton.
/// `items` est appelé au clic (le PDF est écrit à ce moment-là, avec les options en cours).
struct ShareButton: NSViewRepresentable {
    let title: String
    let items: () -> [Any]

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        context.coordinator.items = items
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    final class Coordinator: NSObject {
        var items: () -> [Any]
        init(items: @escaping () -> [Any]) { self.items = items }

        @objc func share(_ sender: NSButton) {
            let content = items()
            guard !content.isEmpty else { return }
            NSSharingServicePicker(items: content).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
