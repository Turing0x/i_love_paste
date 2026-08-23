import Foundation

/// Tipo de contenido de un elemento del portapapeles.
///
/// El orden de los casos refleja la prioridad de captura: cuando el pasteboard
/// ofrece varias representaciones del mismo contenido, gana la de mayor
/// prioridad (`file` antes que `image`, `image` antes que `richText`, etc.).
/// Ver `ContentKind.captureOrder`.
public enum ContentKind: String, Codable, Sendable, CaseIterable {
    case file
    case image
    case richText
    case url
    case text

    /// Prioridad de captura, de mayor a menor.
    public static let captureOrder: [ContentKind] = [.file, .image, .richText, .url, .text]

    /// `true` si el contenido vive en disco (`ClipboardItem.blobPath`) en vez de
    /// dentro de la fila de la base de datos.
    public var isBlobBacked: Bool {
        switch self {
        case .file, .image: return true
        case .richText, .url, .text: return false
        }
    }
}
