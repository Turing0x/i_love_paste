import PasteCore
import SwiftUI

/// Historial del portapapeles.
///
/// La lista se alimenta de `observeItems`, así que se actualiza sola al copiar
/// sin que el capturador tenga que avisar a nadie.
struct HistoryView: View {
    let environment: AppEnvironment

    @State private var items: [ClipboardItem] = []
    @State private var error: String?
    @State private var copiedID: UUID?
    @State private var renamingItem: ClipboardItem?

    var body: some View {
        VStack(spacing: 0) {
            if let error = environment.openError ?? error {
                ErrorBanner(message: error)
            }
            list
            statusBar
        }
        .task { await observe() }
        .sheet(item: $renamingItem) { item in
            RenameSheet(item: item) { newTitle in
                perform { try environment.store?.rename(id: item.id, to: newTitle) }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(items) { item in
                ItemRow(
                    item: item,
                    icon: item.sourceBundleID.flatMap { environment.icons.icon(forBundleID: $0) },
                    justCopied: copiedID == item.id
                )
                .contentShape(Rectangle())
                .onTapGesture { copy(item) }
                .contextMenu {
                    Button("Copiar") { copy(item) }
                    Button("Renombrar…") { renamingItem = item }
                    Divider()
                    Button("Borrar", role: .destructive) {
                        perform { try environment.store?.softDelete(id: item.id) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if items.isEmpty && environment.openError == nil {
                ContentUnavailableView(
                    "Historial vacío",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copia algo y aparecerá aquí.")
                )
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Toggle("Pausar captura", isOn: Binding(
                get: { environment.isPaused },
                set: { environment.isPaused = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            // Mostrar por qué se descartó lo último evita la pregunta "¿por qué
            // no se ha guardado esto que acabo de copiar?".
            if let skip = environment.watcher?.lastSkip {
                Text(skip.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func observe() async {
        guard let store = environment.store else { return }
        do {
            for try await fresh in store.observeItems(limit: 500) {
                items = fresh
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func copy(_ item: ClipboardItem) {
        environment.writer?.write(item)
        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == item.id { copiedID = nil }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Fila

private struct ItemRow: View {
    let item: ClipboardItem
    let icon: NSImage?
    let justCopied: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            }

            Spacer()

            if justCopied {
                Label("Copiado", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.red.opacity(0.1))
    }
}

private struct RenameSheet: View {
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

private extension ContentKind {
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

private extension SkipReason {
    var explanation: String {
        switch self {
        case .unchanged: ""
        case .concealed: "Último copiado omitido: contenido protegido"
        case .transient: "Último copiado omitido: contenido temporal"
        case .paused: "Captura en pausa"
        case .excludedApp: "Último copiado omitido: app excluida"
        case .unsupportedType: "Último copiado omitido: tipo no soportado todavía"
        case .tooLarge: "Último copiado omitido: demasiado grande"
        case .empty: ""
        }
    }
}
