#if canImport(UniformTypeIdentifiers)
import Foundation
import UniformTypeIdentifiers

/// Carga de contenido desde un `NSItemProvider`.
///
/// Lo usan el botón de pegar de la app y la Share Extension, que reciben el
/// contenido por el mismo mecanismo. Las cargas se quedan en el actor principal:
/// `NSItemProvider` no es `Sendable`, y sacarlo de ahí solo serviría para tener
/// que prometer algo que no es cierto.
@MainActor
extension NSItemProvider {
    /// Envuelve la carga por callback, que es la única que ofrece
    /// `NSItemProvider` para objetos, en algo que se pueda esperar.
    public func loadObject<T: NSItemProviderReading>(_ type: T.Type) async -> T? {
        guard canLoadObject(ofClass: type) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: UncheckedBox(object as? T))
            }
        }.value
    }

    public func loadData(type identifier: String) async -> Data? {
        guard hasItemConformingToTypeIdentifier(identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Texto y tipos de una lista de proveedores, listos para `CaptureEngine`.
    ///
    /// No se consulta el portapapeles en ningún momento: cualquier acceso, por
    /// inocente que parezca, dispara el aviso "Paste ha pegado desde…".
    public static func snapshot(from providers: [NSItemProvider]) async -> PasteboardSnapshot? {
        var text: String?
        var isURL = false
        var rtf: Data?

        for provider in providers {
            if let url = await provider.loadObject(NSURL.self) {
                text = (url as URL).absoluteString
                isURL = true
                break
            }
            if rtf == nil {
                rtf = await provider.loadData(type: PasteboardTypes.rtf)
            }
            if text == nil, let string = await provider.loadObject(NSString.self) {
                text = string as String
            }
        }

        guard text != nil || rtf != nil else { return nil }

        var types: Set<String> = [PasteboardTypes.utf8PlainText]
        if isURL { types.insert(PasteboardTypes.url) }
        if rtf != nil { types.insert(PasteboardTypes.rtf) }

        // El contador no se usa por esta vía: quien la llama pasa
        // `lastChangeCount: -1`, así que la comprobación de "no ha cambiado"
        // nunca se activa.
        return PasteboardSnapshot(changeCount: 0, types: types, string: text, rtf: rtf)
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
#endif
