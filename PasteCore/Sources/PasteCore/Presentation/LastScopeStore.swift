import Foundation

/// Persiste el último ámbito visitado (historial, todo, o un pinboard) para
/// que la próxima apertura vuelva ahí directamente.
///
/// Va en `UserDefaults` y no en la base de datos por la misma razón que
/// `CaptureSettingsStore`: es estado de la interfaz, no un dato del usuario.
public struct LastScopeStore {
    private enum Key {
        static let kind = "lastScope.kind"
        static let pinboardID = "lastScope.pinboardID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HistoryFilter.Scope {
        switch defaults.string(forKey: Key.kind) {
        case "everything":
            return .everything
        case "pinboard":
            guard let raw = defaults.string(forKey: Key.pinboardID),
                  let id = UUID(uuidString: raw)
            else { return .history }
            return .pinboard(id)
        default:
            return .history
        }
    }

    public func save(_ scope: HistoryFilter.Scope) {
        switch scope {
        case .history:
            defaults.set("history", forKey: Key.kind)
            defaults.removeObject(forKey: Key.pinboardID)
        case .everything:
            defaults.set("everything", forKey: Key.kind)
            defaults.removeObject(forKey: Key.pinboardID)
        case .pinboard(let id):
            defaults.set("pinboard", forKey: Key.kind)
            defaults.set(id.uuidString, forKey: Key.pinboardID)
        }
    }
}
