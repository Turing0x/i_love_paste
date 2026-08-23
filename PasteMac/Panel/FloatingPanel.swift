import AppKit

/// Panel flotante que recibe teclado sin activar la aplicación.
///
/// Es la pieza de la que depende todo el flujo: al abrirlo, la app que tenías
/// delante sigue siendo la activa, así que al cerrarlo vuelves justo donde
/// estabas y en M3 habrá a quién enviarle el ⌘V del Direct Paste.
final class FloatingPanel: NSPanel {
    /// Sin esto no se puede escribir en el buscador: un panel que no puede ser
    /// la ventana clave no recibe eventos de teclado.
    override var canBecomeKey: Bool { true }

    /// Pero nunca es la ventana principal, que es lo que haría que el sistema
    /// considerase activa a la aplicación.
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // `.titled` con `.fullSizeContentView` en vez de `.borderless`:
            // regala esquinas redondeadas y sombra, y el manejo de teclado es
            // más fiable que en una ventana sin marco.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isFloatingPanel = true
        level = .floating
        // Sin esto el panel se escondería solo cada vez que otra app pasa al
        // frente, que es exactamente lo que ocurre siempre al abrirlo.
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        // Aparece en el escritorio activo y también sobre apps a pantalla
        // completa, no solo en el espacio donde se creó.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Esc cierra el panel. Llega por aquí porque `NSResponder` traduce la tecla
    /// a esta acción antes de que la vea ninguna vista.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
