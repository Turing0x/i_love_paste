import AppKit
import PasteCore

/// Extrae una `PasteboardSnapshot` de `NSPasteboard`.
///
/// Es la única parte del capturador que conoce AppKit. Todo lo que decide qué
/// hacer con el contenido vive en `CaptureEngine`, dentro de `PasteCore`.
@MainActor
struct NSPasteboardSnapshotReader {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot {
        // El contador se lee lo primero: si el portapapeles cambiase mientras
        // extraemos el contenido, guardar el contador posterior nos haría
        // perder esa escritura para siempre.
        let changeCount = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))

        return PasteboardSnapshot(
            changeCount: changeCount,
            types: types,
            string: pasteboard.string(forType: .string),
            rtf: pasteboard.data(forType: .rtf),
            declaredSourceBundleID: pasteboard.string(
                forType: NSPasteboard.PasteboardType(PasteboardTypes.source)
            )
        )
    }

    /// App en primer plano en este instante, como mejor apuesta sobre quién
    /// copió.
    func frontmostApp() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier
        else { return nil }
        return SourceApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
