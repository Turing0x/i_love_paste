import Foundation

/// Qué hacer con una fotografía del portapapeles.
public enum CaptureDecision: Equatable, Sendable {
    case capture(ClipboardItem)
    case skip(SkipReason)
}

/// Por qué se descartó un contenido.
///
/// Es un enum y no un booleano porque "¿por qué no se ha guardado esto que
/// acabo de copiar?" es una pregunta que surge sola al usar la app, y sin este
/// dato no tiene respuesta.
public enum SkipReason: String, Equatable, Sendable {
    /// El portapapeles no ha cambiado desde la última comprobación.
    case unchanged
    /// Marcado como `org.nspasteboard.ConcealedType`: contraseña o similar.
    case concealed
    /// Marcado como transitorio o autogenerado.
    case transient
    case paused
    case excludedApp
    /// Tipo que este hito todavía no maneja (ficheros e imágenes llegan en M2).
    case unsupportedType
    case tooLarge
    /// No había nada aprovechable en el portapapeles.
    case empty
}
