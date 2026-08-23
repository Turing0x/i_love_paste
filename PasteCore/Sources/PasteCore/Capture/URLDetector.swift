import Foundation

/// Decide si un texto suelto es, en realidad, un enlace.
///
/// Hace falta porque copiar una URL desde un terminal o un editor no declara el
/// tipo `public.url`: llega como texto pelado, y sin esto acabaría en el
/// historial como texto en vez de como enlace.
public enum URLDetector {
    /// `true` si el texto **entero** es una URL http(s).
    ///
    /// Una frase que *contenga* una URL no cuenta: si alguien copia un párrafo
    /// con un enlace dentro, lo que quiere reutilizar es el párrafo.
    public static func isWholeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              // Un espacio interior significa que hay más cosas además de la URL.
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else { return false }
        return true
    }
}
