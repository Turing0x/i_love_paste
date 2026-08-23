import Foundation
import PasteCore

extension UserDefaults {
    /// Preferencias de esta instancia.
    ///
    /// Dos copias de la app en el mismo Mac comparten dominio de `UserDefaults`
    /// porque comparten identificador de paquete, así que también compartirían
    /// el `deviceID`. Sincronizar dos instancias que se creen el mismo
    /// dispositivo no probaría nada, de modo que la instancia de depuración
    /// recibe su propio dominio.
    static var pasteInstance: UserDefaults {
        #if DEBUG
        if let override = AppPaths.debugContainerOverride {
            let suite = "dev.threedots.paste.debug." + override.lastPathComponent
            if let defaults = UserDefaults(suiteName: suite) { return defaults }
        }
        #endif
        return .standard
    }
}
