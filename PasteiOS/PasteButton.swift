import PasteCore
import SwiftUI
import UIKit

/// Botón de pegar del sistema.
///
/// Es `UIPasteControl` y no un botón propio porque es lo único que da acceso al
/// portapapeles **sin** el aviso "Paste ha pegado desde…", que desde iOS 16
/// aparece en cada lectura. El sistema entrega el contenido solo cuando el
/// usuario pulsa, así que no hay captura silenciosa que valga (§39).
struct PasteButton: UIViewRepresentable {
    let onCapture: (PasteboardSnapshot) -> Void

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .capsule

        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onCapture = onCapture
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    /// Recibe lo pegado y lo convierte en una `PasteboardSnapshot`.
    ///
    /// La conversión vive aquí y la política en `CaptureEngine`, igual que en el
    /// Mac: lo específico de la plataforma se queda en la app, y lo que decide
    /// qué se guarda es el mismo código en los dos sistemas.
    @MainActor
    final class Coordinator: UIResponder {
        var onCapture: (PasteboardSnapshot) -> Void

        init(onCapture: @escaping (PasteboardSnapshot) -> Void) {
            self.onCapture = onCapture
            super.init()
            // Los tipos se dan de una vez en el inicializador: el conjunto que
            // crea `UIPasteConfiguration(forAccepting:)` es inmutable, y
            // añadirle tipos después revienta la app al arrancar.
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
                PasteboardTypes.url,
                PasteboardTypes.rtf,
                PasteboardTypes.utf8PlainText
            ])
        }

        override func paste(itemProviders: [NSItemProvider]) {
            // Aquí no se toca `UIPasteboard` ni para leer metadatos: cualquier
            // acceso, por inocente que parezca, dispara el aviso "Paste ha
            // pegado desde…", que es precisamente lo que `UIPasteControl` viene
            // a evitar. Todo sale de los proveedores, que es lo que el sistema
            // acaba de entregar con permiso explícito del usuario.
            //
            // La extracción vive en `PasteCore` porque la Share Extension recibe
            // el contenido por el mismo mecanismo.
            Task { @MainActor in
                guard let snapshot = await NSItemProvider.snapshot(from: itemProviders) else {
                    return
                }
                onCapture(snapshot)
            }
        }
    }
}
