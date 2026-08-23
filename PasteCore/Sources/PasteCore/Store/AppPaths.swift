import Foundation

/// Rutas donde viven la base de datos y los blobs.
///
/// Están en `PasteCore` y no en cada app porque la del Mac, la del iPhone y las
/// extensiones de iOS tienen que coincidir exactamente: si cada una calculase la
/// suya, acabarían leyendo historiales distintos.
public enum AppPaths {
    /// Contenedor de la app.
    ///
    /// Con `appGroup` se devuelve el contenedor compartido, que es la única
    /// forma de que una extensión de iOS (teclado, share) vea los mismos datos
    /// que la app anfitriona.
    public static func container(appGroup: String? = nil) throws -> URL {
        if let appGroup,
           let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return shared
        }
        return try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Paste", isDirectory: true)
    }

    public static func databaseURL(appGroup: String? = nil) throws -> URL {
        try container(appGroup: appGroup).appendingPathComponent("paste.sqlite")
    }

    public static func blobsURL(appGroup: String? = nil) throws -> URL {
        try container(appGroup: appGroup).appendingPathComponent("blobs", isDirectory: true)
    }
}
