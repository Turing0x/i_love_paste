import AppKit
import SwiftUI

/// Muestra y esconde el panel flotante.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var makeContent: (() -> AnyView)?

    private static let size = NSSize(width: 620, height: 460)

    /// App que estaba delante cuando se abrió el panel.
    ///
    /// M2 no la usa. Se guarda ya porque es exactamente lo que M3 necesitará
    /// para saber a quién enviarle el ⌘V del Direct Paste, y en ese momento ya
    /// será tarde para averiguarlo.
    private(set) var targetApplication: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(content: @escaping () -> AnyView) {
        makeContent = content
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard let makeContent else { return }
        targetApplication = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: makeContent())
        panel.setFrame(frameForActiveScreen(), display: true)
        // No se llama a `NSApp.activate`: activar la app rompería justo lo que
        // este panel existe para conservar.
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        // Basta con retirarlo: con `.nonactivatingPanel` la otra app nunca dejó
        // de estar activa, así que no hay foco que devolver.
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// Centrado horizontalmente y a un tercio de la altura, en la pantalla donde
    /// esté el ratón.
    ///
    /// Con varios monitores, aparecer siempre en el principal obliga a cruzar el
    /// escritorio con la vista cada vez.
    private func frameForActiveScreen() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        return NSRect(
            x: visible.midX - Self.size.width / 2,
            y: visible.midY - Self.size.height / 2 + visible.height / 6,
            width: Self.size.width,
            height: Self.size.height
        )
    }

    // MARK: - NSWindowDelegate

    /// Pulsar fuera del panel lo cierra.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
