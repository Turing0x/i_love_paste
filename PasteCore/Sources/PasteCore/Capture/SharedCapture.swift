import Foundation

/// Puerta de entrada de contenido en iOS.
///
/// La app y la Share Extension son procesos distintos y no comparten target,
/// pero tienen que guardar exactamente igual: un tipo protegido, un texto
/// demasiado grande o una pausa activa deben tratarse igual vengan por donde
/// vengan. Esto es lo que lo garantiza — abre la base del grupo compartido,
/// aplica `CaptureEngine` y guarda.
public struct SharedCapture {
    public let store: ClipboardStore
    private let settings: CaptureSettingsStore

    /// Abre la base del grupo compartido.
    ///
    /// Lanza si el grupo no está disponible, en vez de caer a un contenedor
    /// propio: dos historiales separados que nadie ve es peor que un error.
    public init(appGroup: String = AppPaths.sharedGroupIdentifier) throws {
        let url = try AppPaths.databaseURL(appGroup: appGroup)
        self.store = ClipboardStore(try AppDatabase.open(at: url))
        self.settings = CaptureSettingsStore(
            defaults: UserDefaults(suiteName: appGroup) ?? .standard
        )
    }

    public var deviceID: UUID { settings.deviceID() }

    /// Guarda una instantánea si la política de captura lo permite.
    ///
    /// - Parameters:
    ///   - source: a qué se atribuye el contenido. La extensión pasa
    ///     `SharedCapture.sharedSheet` porque iOS no permite saber de forma
    ///     fiable desde qué app se compartió.
    ///   - pinboardID: destino directo, para el "guardar en un pinboard" de §35.
    /// - Returns: el elemento guardado, o `nil` si se descartó.
    @discardableResult
    public func capture(
        _ snapshot: PasteboardSnapshot,
        source: SourceApp? = nil,
        pinboardID: UUID? = nil
    ) throws -> ClipboardItem? {
        let engine = CaptureEngine(settings: settings.load(), deviceID: settings.deviceID())

        // `lastChangeCount: -1` porque por esta vía siempre hay intención
        // explícita del usuario: no hay sondeo del que defenderse.
        guard case .capture(let item) = engine.decide(
            snapshot,
            lastChangeCount: -1,
            frontmost: source
        ) else { return nil }

        let stored = try store.capture(item)
        if let pinboardID {
            try store.move(id: stored.id, toPinboard: pinboardID)
        }
        return stored
    }

    /// Origen de lo que llega por la hoja de compartir.
    ///
    /// iOS no deja saber la app de procedencia, y dejarlo vacío haría que las
    /// filas dijeran "Origen desconocido". Esto es honesto y además crea una
    /// entrada útil en el filtro por app.
    public static let sharedSheet = SourceApp(
        bundleID: "dev.threedots.paste.share",
        name: "Compartido"
    )
}
