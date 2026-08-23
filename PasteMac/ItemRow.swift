import AppKit
import PasteCore
import SwiftUI

/// Una fila del historial.
struct ItemRow: View {
    let item: ClipboardItem
    let icon: NSImage?
    /// Número de Quick Paste, si el elemento está entre los nueve primeros.
    let quickPasteNumber: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(item.sourceAppName ?? "Origen desconocido")
                    Text("·")
                    Text(item.createdAt, format: .relative(presentation: .numeric))
                }
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            // Mostrar el número hace que Quick Paste se descubra solo, sin
            // tener que leer ninguna documentación.
            if let quickPasteNumber {
                Text("⌘\(quickPasteNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : .clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// Hoja para poner un título a mano a un elemento.
struct RenameSheet: View {
    let item: ClipboardItem
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renombrar elemento").font(.headline)
            TextField("Título", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                // Vaciar el campo devuelve el título derivado del contenido.
                Button("Quitar título") {
                    onSave(nil)
                    dismiss()
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Guardar") {
                    onSave(title.isEmpty ? nil : title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear { title = item.title ?? "" }
    }
}

// MARK: - Presentación

extension ContentKind {
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var label: String {
        switch self {
        case .text: "Texto"
        case .richText: "Formato"
        case .url: "Enlace"
        case .image: "Imagen"
        case .file: "Fichero"
        }
    }

    /// Tipos que el capturador produce hoy. Imágenes y ficheros llegan más
    /// adelante, y ofrecerlos como filtro solo daría listas siempre vacías.
    static let filterable: [ContentKind] = [.text, .richText, .url]
}

extension SkipReason {
    var explanation: String {
        switch self {
        case .unchanged, .empty: ""
        case .concealed: "Último copiado omitido: contenido protegido"
        case .transient: "Último copiado omitido: contenido temporal"
        case .paused: "Captura en pausa"
        case .excludedApp: "Último copiado omitido: app excluida"
        case .unsupportedType: "Último copiado omitido: tipo no soportado todavía"
        case .tooLarge: "Último copiado omitido: demasiado grande"
        }
    }
}
