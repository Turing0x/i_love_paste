import AppKit

/// Resuelve iconos de aplicación por bundle ID.
///
/// Los iconos no se guardan en la base de datos: son derivables del bundle ID,
/// cambian cuando el usuario actualiza la app, y meterlos en cada fila del
/// historial multiplicaría su tamaño sin aportar nada que no se pueda recalcular.
@MainActor
@Observable
final class AppIconCache {
    private var cache: [String: NSImage] = [:]

    /// Icono de la app, o `nil` si ya no está instalada.
    ///
    /// El resultado se cachea incluso cuando es `nil`, para no volver a
    /// preguntar al sistema por cada fila en cada redibujado.
    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
