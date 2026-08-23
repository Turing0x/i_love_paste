import CryptoKit
import Foundation

/// Calcula la huella que identifica un contenido a efectos de deduplicación.
public enum ContentHasher {
    /// Huella de un texto.
    ///
    /// Lo que no se toca son mayúsculas ni espacios interiores: en código sí
    /// importan.
    public static func hash(text: String) -> String {
        digest(Data(normalize(text).utf8), prefix: "t")
    }

    /// Huella de un contenido con formato.
    ///
    /// Entra el RTF además del texto porque `ClipboardStore.capture` no
    /// actualiza `richData` al deduplicar: si el hash ignorase el formato,
    /// copiar el mismo texto con otro estilo ascendería el elemento viejo y
    /// dejaría guardado un formato que ya no corresponde a lo que se copió.
    public static func hash(richText text: String, rtf: Data) -> String {
        var combined = Data(normalize(text).utf8)
        combined.append(rtf)
        return digest(combined, prefix: "r")
    }

    /// Unifica los saltos de línea y recorta los extremos: copiar el mismo
    /// fragmento desde dos apps distintas suele diferir solo en eso.
    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Huella de un contenido binario (imagen o fichero).
    public static func hash(data: Data) -> String {
        digest(data, prefix: "b")
    }

    /// Huella de un conjunto de rutas de fichero.
    ///
    /// Se ordenan porque el pasteboard no garantiza el orden y seleccionar los
    /// mismos ficheros dos veces no debería producir dos elementos.
    public static func hash(fileURLs: [URL]) -> String {
        let joined = fileURLs.map(\.standardizedFileURL.path).sorted().joined(separator: "\n")
        return digest(Data(joined.utf8), prefix: "f")
    }

    /// El prefijo evita que un texto y un binario con los mismos bytes colisionen
    /// bajo el índice único de `contentHash`.
    private static func digest(_ data: Data, prefix: String) -> String {
        let hash = SHA256.hash(data: data)
        return prefix + ":" + hash.map { String(format: "%02x", $0) }.joined()
    }
}
