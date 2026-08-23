import Foundation

/// Preferencias que gobiernan qué se captura y qué no.
///
/// Van en `UserDefaults`, no en la base de datos: no son datos del usuario que
/// haya que buscar, sincronizar ni conservar en el historial.
public struct CaptureSettings: Equatable, Sendable {
    /// Detiene la captura sin parar el vigilante: lo copiado durante la pausa se
    /// descarta, no se acumula para después.
    public var isPaused: Bool

    /// Apps cuyo contenido nunca se guarda.
    public var excludedBundleIDs: Set<String>

    /// Tope de tamaño del texto. Un volcado de log de varios megabytes no aporta
    /// nada al historial y sí infla el índice de búsqueda.
    public var maxTextBytes: Int

    public init(
        isPaused: Bool = false,
        excludedBundleIDs: Set<String> = CaptureSettings.defaultExcludedBundleIDs,
        maxTextBytes: Int = 5 * 1024 * 1024
    ) {
        self.isPaused = isPaused
        self.excludedBundleIDs = excludedBundleIDs
        self.maxTextBytes = maxTextBytes
    }

    /// Gestores de contraseñas conocidos.
    ///
    /// Es cinturón además de tirantes: los que se portan bien ya marcan lo que
    /// copian como `ConcealedType` y se descartarían igual, pero no todos lo
    /// hacen y el coste de equivocarse aquí es guardar una contraseña en claro.
    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.Dashlane",
        "in.sinew.Enpass-Desktop"
    ]

    public static let `default` = CaptureSettings()
}
