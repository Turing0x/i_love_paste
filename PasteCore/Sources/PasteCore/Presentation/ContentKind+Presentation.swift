import Foundation

/// Cómo se enseña un tipo de contenido.
///
/// Vive en `PasteCore` y no en cada app porque el Mac y el iPhone tienen que
/// llamar a las cosas igual: un filtro que se llame "Enlace" en un sitio y
/// "URL" en el otro es la misma función con dos nombres.
extension ContentKind {
    public var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    public var label: String {
        switch self {
        case .text: "Texto"
        case .richText: "Formato"
        case .url: "Enlace"
        case .image: "Imagen"
        case .file: "Fichero"
        }
    }

    /// Tipos que el capturador produce hoy. Imágenes y ficheros llegan más
    /// adelante, y ofrecerlos como filtro solo daría listas siempre vacías.
    public static let filterable: [ContentKind] = [.text, .richText, .url]
}
