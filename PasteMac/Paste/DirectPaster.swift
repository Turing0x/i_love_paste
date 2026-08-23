import AppKit
import CoreGraphics

/// Envía ⌘V a la aplicación que estaba delante cuando se abrió el panel.
///
/// El destino se recibe desde fuera, no se consulta aquí: para cuando esto se
/// ejecuta el panel ya ha sido la ventana clave, y preguntar por la app
/// frontal en ese momento puede devolver la propia Paste.
@MainActor
struct DirectPaster {
    /// Código de la tecla V. Es una posición física del teclado, no un carácter,
    /// así que sigue siendo la misma en distribuciones no QWERTY.
    private static let keyCodeV: CGKeyCode = 9

    /// Margen entre esconder el panel y sintetizar la pulsación.
    ///
    /// Retirar la ventana clave y devolver el foco no es instantáneo; sin esta
    /// pausa el ⌘V llega a veces antes de que haya nadie escuchando y se pierde
    /// sin dejar rastro.
    private static let focusSettleDelay = Duration.milliseconds(50)

    var isAuthorized: Bool { AccessibilityAuthorization.isTrusted }

    /// Pega en `application`. Devuelve `false` si no se pudo, y entonces el
    /// contenido se queda en el portapapeles para pegarlo a mano.
    @discardableResult
    func paste(into application: NSRunningApplication?) async -> Bool {
        guard isAuthorized else { return false }
        guard let application, !application.isTerminated else { return false }

        // Normalmente ya está activa: el panel no activa a Paste. Pero si el
        // usuario cambió de app con el panel abierto, el destino es el que
        // había al abrirlo, y hay que traerlo de vuelta.
        if !application.isActive {
            application.activate()
        }
        try? await Task.sleep(for: Self.focusSettleDelay)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: Self.keyCodeV,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: Self.keyCodeV,
                  keyDown: false
              )
        else { return false }

        // Las banderas se fijan enteras en vez de añadir Command a las que haya:
        // el atajo que abre el panel es ⌥⌘V y el usuario puede seguir con las
        // teclas pulsadas, lo que convertiría esto en ⌥⌘V otra vez.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Al nivel del tap de hardware: es donde lo esperan las apps que filtran
        // eventos de sesión, y el que trata igual a Electron y a las nativas.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
