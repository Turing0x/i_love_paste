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
            Task { @MainActor in
                var text: String?
                var isURL = false
                var rtf: Data?

                for provider in itemProviders {
                    if let url = await provider.load(NSURL.self) {
                        text = (url as URL).absoluteString
                        isURL = true
                        break
                    }
                    if rtf == nil {
                        rtf = await provider.loadData(type: PasteboardTypes.rtf)
                    }
                    if text == nil, let string = await provider.load(NSString.self) {
                        text = string as String
                    }
                }

                var types: Set<String> = [PasteboardTypes.utf8PlainText]
                // Que sea un enlace lo decide haber podido cargar una `NSURL`
                // del proveedor: es lo que hace que el motor lo clasifique como
                // `url` y no como texto suelto.
                if isURL { types.insert(PasteboardTypes.url) }
                if rtf != nil { types.insert(PasteboardTypes.rtf) }

                onCapture(PasteboardSnapshot(
                    // El contador no se usa por esta vía: el motor recibe
                    // `lastChangeCount: -1`, así que la comprobación de "no ha
                    // cambiado" nunca se activa. Leerlo del portapapeles solo
                    // serviría para provocar el aviso.
                    changeCount: 0,
                    types: types,
                    string: text,
                    rtf: rtf
                ))
            }
        }
    }
}

/// Las cargas se quedan en el actor principal: `NSItemProvider` no es
/// `Sendable`, y sacarlo de aquí solo serviría para tener que prometer algo que
/// no es cierto.
@MainActor
private extension NSItemProvider {
    /// Envuelve la carga por callback, que es la única que ofrece `NSItemProvider`
    /// para objetos, en algo que se pueda esperar.
    func load<T: NSItemProviderReading>(_ type: T.Type) async -> T? {
        guard canLoadObject(ofClass: type) else { return nil }
        // El resultado se transporta como `Data`/`String` inmediatamente después:
        // `NSString` y `NSURL` no son `Sendable`, así que se convierten dentro
        // del propio callback en vez de cruzar el límite tal cual.
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: UncheckedBox(object as? T))
            }
        }.value
    }

    func loadData(type identifier: String) async -> Data? {
        guard hasItemConformingToTypeIdentifier(identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// Caja para devolver un objeto de Foundation desde un callback.
///
/// `NSString` y `NSURL` no son `Sendable`, pero aquí el objeto lo crea el
/// callback y lo consume un único punto en el actor principal: no hay acceso
/// concurrente que proteger.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T?

    init(_ value: T?) {
        self.value = value
    }
}
