import CryptoKit
import Foundation

/// Calcula la huella que identifica un contenido a efectos de deduplicación.
public enum ContentHasher {
    /// Huella de un texto.
    ///
    /// Se normalizan los saltos de línea y se recortan los espacios de los
    /// extremos, porque copiar el mismo fragmento desde dos apps distintas suele
    /// diferir solo en eso y son, para el usuario, el mismo contenido. Lo que no
    /// se toca son mayúsculas ni espacios interiores: en código sí importan.
    public static func hash(text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return digest(Data(normalized.utf8), prefix: "t")
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
