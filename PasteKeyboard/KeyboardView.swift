import PasteCore
import SwiftUI

/// Contenido del teclado: pestañas de ámbito y lista de elementos.
struct KeyboardView: View {
    let hasFullAccess: Bool

    /// Sin acceso completo esto vale `true`: no se puede comprobar, y el aviso
    /// que toca enseñar entonces es el del permiso.
    let isSubscribed: Bool

    /// La base la abre el controlador, una vez. Aquí solo se lee: recrearla en
    /// cada cambio de pestaña era el error que había.
    let store: ClipboardStore?

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
            if !hasFullAccess {
                fullAccessNotice
            } else if !isSubscribed {
                subscriptionNotice
            } else {
                scopeTabs
                Divider()
                list
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

    /// Un teclado no puede abrir la app —no tiene `openURL`—, así que esto solo
    /// puede decir dónde se arregla.
    private var subscriptionNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Suscripción requerida")
                .font(.callout.bold())
            Text("Abre la app de Paste para suscribirte.")
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
            // La pestaña activa se distingue solo por el tinte.
            .accessibilityAddTraits(scope == target ? .isSelected : [])
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
                    .accessibilityLabel("\(item.kind.label): \(item.displayTitle)")
                    .accessibilityHint("Toca dos veces para insertarlo")
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
                        // Mínimo táctil: es la única salida del teclado y estaba
                        // del tamaño del glifo.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .accessibilityLabel("Siguiente teclado")
            }
            Spacer()
        }
    }

    // MARK: - Datos

    /// Lectura puntual, sin `ValueObservation`: el teclado aparece, se usa y se
    /// va. Mantener una observación viva costaría más de lo que ahorra.
    private func load() {
        guard hasFullAccess else { return }
        guard let store else {
            error = "Sin acceso al historial"
            return
        }
        do {
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
