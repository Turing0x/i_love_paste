import Foundation

/// Rutas donde viven la base de datos y los blobs.
///
/// Están en `PasteCore` y no en cada app porque la del Mac, la del iPhone y las
/// extensiones de iOS tienen que coincidir exactamente: si cada una calculase la
/// suya, acabarían leyendo historiales distintos.
/// Fallos al resolver dónde vive la base de datos.
public enum AppPathsError: LocalizedError, Equatable {
    /// Se pidió el contenedor compartido y el sistema no lo entregó.
    case appGroupUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let group):
            """
            No hay acceso al grupo compartido «\(group)».
            Suele significar que el entitlement de App Group no llegó al binario \
            firmado. Sin él, la app y sus extensiones acabarían con historiales \
            distintos.
            """
        }
    }
}

public enum AppPaths {
    /// Grupo que comparten la app de iPhone y sus extensiones.
    ///
    /// Vive aquí y no en cada target porque basta con que uno lo escriba
    /// distinto para que la extensión guarde en un historial que la app no ve.
    ///
    /// El Mac no lo usa: no tiene extensiones, y moverle la base ahora dejaría
    /// huérfano el historial que ya tiene.
    public static let sharedGroupIdentifier = "group.dev.threedots.paste"

    /// Contenedor de la app.
    ///
    /// Con `appGroup` se devuelve el contenedor compartido, que es la única
    /// forma de que una extensión de iOS (teclado, share) vea los mismos datos
    /// que la app anfitriona.
    public static func container(appGroup: String? = nil) throws -> URL {
        #if DEBUG
        // Segunda instancia para probar la sincronización. Sin esto no hay forma
        // de ver la ida y vuelta hasta que exista el iPhone: dos copias de la
        // app en el mismo Mac compartirían base y no se sincronizarían con nada.
        if let override = debugContainerOverride { return override }
        #endif

        if let appGroup {
            // Si se pidió el grupo y el sistema no lo da, se falla en vez de
            // caer al contenedor propio.
            //
            // El fallback silencioso es peor que el error: la app arrancaría
            // aparentando normalidad mientras sus extensiones escriben en un
            // historial que ella no lee, y eso se descubre tarde y con los datos
            // ya partidos en dos. Que no haya grupo significa casi siempre un
            // entitlement que no llegó al binario.
            guard let shared = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            else {
                throw AppPathsError.appGroupUnavailable(appGroup)
            }
            return shared
        }
        return try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Paste", isDirectory: true)
    }

    #if DEBUG
    /// Contenedor alternativo indicado por `PASTE_DB_PATH`.
    ///
    /// Solo en compilaciones de depuración: en una app instalada, una variable
    /// de entorno no debería poder mover el historial del usuario.
    public static var debugContainerOverride: URL? {
        ProcessInfo.processInfo.environment["PASTE_DB_PATH"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }
    #endif

    public static func databaseURL(appGroup: String? = nil) throws -> URL {
        try container(appGroup: appGroup).appendingPathComponent("paste.sqlite")
    }

    public static func blobsURL(appGroup: String? = nil) throws -> URL {
        try container(appGroup: appGroup).appendingPathComponent("blobs", isDirectory: true)
    }
}
