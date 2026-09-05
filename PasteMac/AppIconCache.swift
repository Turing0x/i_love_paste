import AppKit

/// Resuelve iconos de aplicación por bundle ID.
///
/// Los iconos no se guardan en la base de datos: son derivables del bundle ID,
/// cambian cuando el usuario actualiza la app, y meterlos en cada fila del
/// historial multiplicaría su tamaño sin aportar nada que no se pueda recalcular.
///
/// **No es `@Observable` a propósito.** La caché se consulta desde el `body` de
/// las filas, y consultarla escribe: con Observation, leer y mutar una
/// propiedad rastreada durante el pintado invalida la vista que la acaba de
/// leer. Nadie necesita enterarse de que la caché ha crecido —el icono ya se
/// devuelve en la misma llamada—, así que aquí observar solo servía para
/// repintar de más.
@MainActor
final class AppIconCache {
    /// El valor es opcional a propósito: una entrada presente con `nil` dentro
    /// significa "ya se preguntó y esa app no está instalada". Sin eso, cada
    /// fila de una app desinstalada volvía a interrogar a `NSWorkspace` en cada
    /// redibujado, que es justo el caso que la caché tenía que cubrir.
    private var cache: [String: NSImage?] = [:]

    /// Icono de la app, o `nil` si ya no está instalada.
    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }

        let icon = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = icon
        return icon
    }
}
