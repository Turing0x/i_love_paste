import PasteCore
import SwiftUI
import UIKit

/// Teclado de Paste (§37): el historial dentro del teclado, para insertar sin
/// salir de la app en la que estás escribiendo.
final class KeyboardViewController: UIInputViewController {
    /// Un teclado sin altura declarada sale aplastado contra el borde.
    private static let height: CGFloat = 260

    override func viewDidLoad() {
        super.viewDidLoad()

        let view = KeyboardView(
            // Sin acceso completo, iOS prohíbe leer el contenedor compartido:
            // no hay historial que enseñar, y el aviso es lo único que se puede
            // ofrecer.
            hasFullAccess: hasFullAccess,
            store: Self.openStore(hasFullAccess: hasFullAccess),
            needsGlobe: needsInputModeSwitchKey,
            onInsert: { [weak self] text in
                // Esto es "pegar" en un teclado: se escribe en el campo de la
                // app anfitriona. El portapapeles del sistema no se toca.
                self?.textDocumentProxy.insertText(text)
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )

        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    /// Abre la base compartida **una sola vez**, en el arranque del teclado.
    ///
    /// Antes la abría la vista en cada cambio de pestaña: un `DatabasePool`
    /// nuevo, con su migrador, por cada toque. Un teclado tiene el techo de
    /// memoria más bajo de todas las extensiones de iOS y vive unos segundos;
    /// es el último sitio donde conviene abrir conexiones a la ligera.
    ///
    /// Sin acceso completo no se intenta siquiera: el sistema no deja llegar al
    /// contenedor compartido y el único resultado sería un error que ya está
    /// explicado en pantalla.
    private static func openStore(hasFullAccess: Bool) -> ClipboardStore? {
        guard hasFullAccess else { return nil }
        do {
            let url = try AppPaths.databaseURL(appGroup: AppPaths.sharedGroupIdentifier)
            return ClipboardStore(try AppDatabase.open(at: url))
        } catch {
            NSLog("Paste: el teclado no pudo abrir el historial: \(error)")
            return nil
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        guard let inputView else { return }
        let height = inputView.heightAnchor.constraint(equalToConstant: Self.height)
        // Por debajo de `required` para que el sistema pueda romperla al rotar
        // en vez de quejarse por consola.
        height.priority = .defaultHigh
        height.isActive = true
    }
}
