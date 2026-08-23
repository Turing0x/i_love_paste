import Foundation
import PasteCore

/// Persiste las preferencias de captura y la identidad de este Mac.
///
/// Va en `UserDefaults` y no en la base de datos porque no son datos del
/// usuario: no se buscan, no se sincronizan y no forman parte del historial.
struct CaptureSettingsStore {
    private enum Key {
        static let isPaused = "capture.isPaused"
        static let excludedBundleIDs = "capture.excludedBundleIDs"
        static let maxTextBytes = "capture.maxTextBytes"
        static let deviceID = "device.id"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .pasteInstance) {
        self.defaults = defaults
    }

    func load() -> CaptureSettings {
        var settings = CaptureSettings()
        settings.isPaused = defaults.bool(forKey: Key.isPaused)
        // Sin valor guardado se usan las exclusiones por defecto: la primera
        // ejecución debe proteger los gestores de contraseñas sin que nadie
        // configure nada.
        if let excluded = defaults.stringArray(forKey: Key.excludedBundleIDs) {
            settings.excludedBundleIDs = Set(excluded)
        }
        let maxBytes = defaults.integer(forKey: Key.maxTextBytes)
        if maxBytes > 0 {
            settings.maxTextBytes = maxBytes
        }
        return settings
    }

    func save(_ settings: CaptureSettings) {
        defaults.set(settings.isPaused, forKey: Key.isPaused)
        defaults.set(Array(settings.excludedBundleIDs), forKey: Key.excludedBundleIDs)
        defaults.set(settings.maxTextBytes, forKey: Key.maxTextBytes)
    }

    /// Identificador estable de este Mac.
    ///
    /// Se genera una vez y no cambia: cuando llegue la sincronización, es lo que
    /// distingue lo copiado aquí de lo que llegue del iPhone.
    func deviceID() -> UUID {
        if let stored = defaults.string(forKey: Key.deviceID), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Key.deviceID)
        return id
    }
}
