import AppKit
import PasteCore

/// Devuelve un elemento del historial al portapapeles del sistema.
@MainActor
struct ClipboardWriter {
    let pasteboard: NSPasteboard
    /// Se avisa al vigilante de la escritura para que no la confunda con
    /// contenido nuevo del usuario.
    let watcher: PasteboardWatcher

    init(pasteboard: NSPasteboard = .general, watcher: PasteboardWatcher) {
        self.pasteboard = pasteboard
        self.watcher = watcher
    }

    func write(_ item: ClipboardItem) {
        pasteboard.clearContents()

        if item.kind == .richText, let rtf = item.richData {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let text = item.plainText {
            pasteboard.setString(text, forType: .string)
            if item.kind == .url {
                // Declarar el tipo hace que quien pegue reciba un enlace y no
                // una cadena que parece uno.
                pasteboard.setString(text, forType: .URL)
            }
        }

        // El contador se lee al final: tanto `clearContents()` como cada
        // escritura lo incrementan, así que solo el valor posterior identifica
        // el estado que acabamos de dejar.
        watcher.ignoreChange(pasteboard.changeCount)
    }
}
