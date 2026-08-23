import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Un elemento del historial arrastrándose.
    ///
    /// Tipo propio y no `.text`: con texto plano, la barra lateral aceptaría
    /// cualquier cosa soltada desde fuera de la app y habría que adivinar si es
    /// un identificador nuestro o la frase que alguien arrastró de un navegador.
    static let pasteItem = UTType(exportedAs: "dev.threedots.paste.item")

    /// Un pinboard arrastrándose dentro de la barra lateral, para reordenarla.
    static let pasteBoard = UTType(exportedAs: "dev.threedots.paste.pinboard")
}

/// Lo que viaja en un arrastre: solo el identificador.
///
/// El contenido no se copia al portapapeles ni se serializa entero; quien reciba
/// el arrastre lee de la base, que es la única fuente de verdad.
struct ItemTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pasteItem)
    }
}

struct PinboardTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pasteBoard)
    }
}
