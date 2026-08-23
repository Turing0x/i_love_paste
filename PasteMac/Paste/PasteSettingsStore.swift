import Foundation

/// Preferencias del pegado, separadas de las de captura porque gobiernan la
/// salida y no la entrada: una excluye apps del historial, la otra decide qué
/// formato recibe la app de destino.
struct PasteSettingsStore {
    private enum Key {
        static let alwaysPlainText = "paste.alwaysPlainText"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "Pegar siempre como texto plano" (§18, modo global).
    var alwaysPlainText: Bool {
        get { defaults.bool(forKey: Key.alwaysPlainText) }
        nonmutating set { defaults.set(newValue, forKey: Key.alwaysPlainText) }
    }
}
