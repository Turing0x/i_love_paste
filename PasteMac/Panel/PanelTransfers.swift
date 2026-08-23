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

/// Lo que la barra lateral acepta soltar: un elemento del historial o un
/// pinboard que se está reordenando.
///
/// Va en un solo tipo porque una vista admite un único `dropDestination`: con
/// dos apilados el segundo tapa al primero en silencio, y soltar un elemento
/// sobre un pinboard no llegaba a ninguna parte.
///
/// El formato en el cable no cambia: cada caso codifica el mismo JSON que
/// `ItemTransfer` y `PinboardTransfer`, que siguen siendo los que emiten los
/// arrastres.
enum SidebarDrop: Transferable {
    case item(UUID)
    case pinboard(UUID)

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .pasteItem) { drop in
            guard case .item(let id) = drop else { throw TransferError.wrongCase }
            return try JSONEncoder().encode(ItemTransfer(id: id))
        } importing: { data in
            .item(try JSONDecoder().decode(ItemTransfer.self, from: data).id)
        }

        DataRepresentation(contentType: .pasteBoard) { drop in
            guard case .pinboard(let id) = drop else { throw TransferError.wrongCase }
            return try JSONEncoder().encode(PinboardTransfer(id: id))
        } importing: { data in
            .pinboard(try JSONDecoder().decode(PinboardTransfer.self, from: data).id)
        }
    }

    /// Exportar un caso por la representación del otro no debe ocurrir: el
    /// sistema elige la representación que corresponde al tipo del arrastre.
    enum TransferError: Error {
        case wrongCase
    }
}
