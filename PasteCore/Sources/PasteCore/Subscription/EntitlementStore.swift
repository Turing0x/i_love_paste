import Foundation

/// Guarda el último derecho conocido en el grupo compartido.
///
/// Va en `UserDefaults` y no en la base por la misma razón que
/// `CaptureSettingsStore`: no es un dato del usuario ni parte del historial. Y
/// va en el grupo, y no en el suite estándar, porque el widget, el teclado y la
/// Share Extension tienen que poder leerlo sin abrir la app.
///
/// Es una caché, no la verdad: la verdad es StoreKit en el iPhone. Lo que
/// compra es que el arranque en frío decida al instante, sin red, y que a quien
/// paga no le parpadee un muro delante mientras se consulta la tienda.
public struct EntitlementStore {
    private enum Key {
        static let entitlement = "entitlement.current"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Caché del grupo compartido, que es la que ven las extensiones de iOS.
    ///
    /// El Mac no usa grupo y se queda con el suite estándar, igual que hace con
    /// el resto de sus preferencias.
    public static func sharedGroup() -> EntitlementStore {
        EntitlementStore(
            defaults: UserDefaults(suiteName: AppPaths.sharedGroupIdentifier) ?? .standard
        )
    }

    public func load() -> Entitlement? {
        guard let data = defaults.data(forKey: Key.entitlement) else { return nil }
        return try? EntitlementCoding.decoder.decode(Entitlement.self, from: data)
    }

    public func save(_ entitlement: Entitlement?) {
        guard let entitlement else {
            defaults.removeObject(forKey: Key.entitlement)
            return
        }
        guard let data = try? EntitlementCoding.encoder.encode(entitlement) else { return }
        defaults.set(data, forKey: Key.entitlement)
    }
}
