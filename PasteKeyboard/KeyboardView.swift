import PasteCore
import SwiftUI

/// Contenido del teclado: pestañas de ámbito y lista de elementos.
struct KeyboardView: View {
    let hasFullAccess: Bool
    let needsGlobe: Bool
    let onInsert: (String) -> Void
    let onNextKeyboard: () -> Void

    @State private var scope: HistoryFilter.Scope = .history
    @State private var pinboards: [Pinboard] = []
    @State private var items: [ClipboardItem] = []
    @State private var error: String?

    /// Lo justo para llenar la altura del teclado. Un teclado vive segundos y
    /// tiene el techo de memoria más bajo de todas las extensiones: no hay
    /// motivo para traer más.
    private static let limit = 40

    var body: some View {
        VStack(spacing: 0) {
            if hasFullAccess {
                scopeTabs
                Divider()
                list
            } else {
                fullAccessNotice
            }

            Divider()
            bottomBar
        }
        .task { load() }
        .onChange(of: scope) { _, _ in load() }
    }

    // MARK: - Sin permiso

    private var fullAccessNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Activa «Permitir acceso completo»")
                .font(.callout.bold())
            // Se dice para qué se usa el permiso: iOS avisa de que un teclado
            // podrá ver lo que escribes, y dejar esa duda sin respuesta es peor
            // que no pedirlo.
            Text("Ajustes › General › Teclado › Teclados › Paste.\n"
                 + "Paste lo necesita solo para leer tu historial; no envía nada.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Contenido

    private var scopeTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                tab("Recientes", target: .history)
                ForEach(pinboards) { board in
                    tab(board.name, target: .pinboard(board.id))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func tab(_ title: String, target: HistoryFilter.Scope) -> some View {
        Button(title) { scope = target }
            .buttonStyle(.bordered)
            .tint(scope == target ? .accentColor : .secondary)
            .controlSize(.small)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button {
                        guard let text = item.plainText else { return }
                        onInsert(text)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.symbolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(item.displayTitle)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 34)
                }
            }
        }
        .overlay {
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("Nada guardado todavía")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            // Sin el globo el usuario se queda encerrado en el teclado de Paste.
            if needsGlobe {
                Button(action: onNextKeyboard) {
                    Image(systemName: "globe")
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            Spacer()
        }
    }

    // MARK: - Datos

    /// Lectura puntual, sin `ValueObservation`: el teclado aparece, se usa y se
    /// va. Mantener una observación viva costaría más de lo que ahorra.
    private func load() {
        guard hasFullAccess else { return }
        do {
            let url = try AppPaths.databaseURL(appGroup: AppPaths.sharedGroupIdentifier)
            let store = ClipboardStore(try AppDatabase.open(at: url))
            if pinboards.isEmpty {
                pinboards = try store.pinboards()
            }
            items = try store.items(matching: HistoryFilter(scope: scope), limit: Self.limit)
            error = nil
        } catch {
            self.error = "Sin acceso al historial"
        }
    }
}
