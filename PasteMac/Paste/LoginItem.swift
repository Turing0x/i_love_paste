import ServiceManagement

/// Arranque automático al iniciar sesión.
///
/// `SMAppService.mainApp` registra el propio bundle, sin helper ni copia en
/// `~/Library/LaunchAgents`: el sistema lo resuelve por la firma, así que la app
/// tiene que estar en su sitio definitivo —`/Applications`— cuando se active.
/// Movida después, el registro apunta a una ruta que ya no existe.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Devuelve `false` si el sistema rechaza el cambio. El caso habitual es
    /// que el usuario lo tenga desactivado en Ajustes > Elementos de inicio,
    /// donde su decisión manda sobre la de la app.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Paste: no se pudo cambiar el arranque automático: \(error)")
            return false
        }
    }
}
