import Foundation

/// Preferencias del pegado, separadas de las de captura porque gobiernan la
/// salida y no la entrada: una excluye apps del historial, la otra decide qué
/// formato recibe la app de destino.
struct PasteSettingsStore {
    private enum Key {
        static let alwaysPlainText = "paste.alwaysPlainText"
        static let syncEnabled = "sync.enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .pasteInstance) {
        self.defaults = defaults
    }

    /// "Pegar siempre como texto plano" (§18, modo global).
    var alwaysPlainText: Bool {
        get { defaults.bool(forKey: Key.alwaysPlainText) }
        nonmutating set { defaults.set(newValue, forKey: Key.alwaysPlainText) }
    }

    /// Sincronización con iCloud, encendida mientras nadie la apague.
    ///
    /// Se comprueba la ausencia de valor en vez de usar `bool(forKey:)` a secas,
    /// que devolvería `false` la primera vez y dejaría la función apagada sin
    /// que nadie la apagase.
    var syncEnabled: Bool {
        get { defaults.object(forKey: Key.syncEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.syncEnabled) }
    }
}
