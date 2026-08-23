import PasteCore
import SwiftUI
import UIKit
import WidgetKit

/// Pantalla principal: historial, pinboards, búsqueda y filtros.
struct HistoryView: View {
    private let store: ClipboardStore
    private let capture: SharedCapture?
    @State private var model: HistoryListViewModel
    @State private var pinboards: PinboardListViewModel

    /// La sincronización vive en el `AppEnvironment`, pero la vista no lo
    /// necesita entero: le basta con saber si está en marcha y cómo pedirla.
    private let isSyncing: Bool
    private let onSync: () -> Void

    @State private var showingPinboards = false

    init(
        store: ClipboardStore,
        capture: SharedCapture?,
        model: HistoryListViewModel,
        pinboards: PinboardListViewModel,
        isSyncing: Bool,
        onSync: @escaping () -> Void
    ) {
        self.store = store
        self.capture = capture
        _model = State(initialValue: model)
        _pinboards = State(initialValue: pinboards)
        self.isSyncing = isSyncing
        self.onSync = onSync
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle(scopeTitle)
                .navigationBarTitleDisplayMode(.inline)
                // La barra lateral del Mac no cabe en un iPhone: el menú cumple
                // la misma función de cambiar de ámbito.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { scopeMenu }
                    ToolbarItem(placement: .topBarTrailing) { syncButton }
                    ToolbarItem(placement: .topBarTrailing) { PasteButton(onCapture: capture) }
                }
                .searchable(text: $model.query, prompt: "Buscar en el historial")
                .safeAreaInset(edge: .top) { kindFilters }
                .sheet(isPresented: $showingPinboards) {
                    PinboardsView(model: pinboards) { deletedID in
                        // La lista no puede quedarse apuntando a un pinboard que
                        // ya no existe: se vería vacía sin explicación.
                        if model.scope == .pinboard(deletedID) { model.scope = .history }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }
        .onAppear {
            model.start()
            pinboards.start()
        }
        .onDisappear {
            model.stop()
            pinboards.stop()
        }
    }

    /// Sincronizar a mano.
    ///
    /// El push silencioso llega cuando el sistema quiere; esto es el camino para
    /// cuando acabas de copiar algo en el Mac y lo quieres aquí ya.
    @ViewBuilder
    private var syncButton: some View {
        if isSyncing {
            ProgressView()
        } else {
            Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath", action: onSync)
        }
    }

    // MARK: - Lista

    private var list: some View {
        List {
            ForEach(model.items) { item in
                ItemRow(item: item)
                    .contentShape(.rect)
                    .onTapGesture { copy(item) }
                    .swipeActions(edge: .trailing) {
                        Button("Borrar", role: .destructive) { delete(item) }
                    }
                    .swipeActions(edge: .leading) {
                        if item.pinboardID != nil {
                            Button("Quitar") { move(item, to: nil) }
                                .tint(.orange)
                        }
                    }
                    .contextMenu { menu(for: item) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "Historial vacío" : "Sin resultados",
                    systemImage: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                    description: Text(
                        model.query.isEmpty
                            ? "Lo que copies en el Mac aparecerá aquí."
                            : "Prueba con otra búsqueda o quita algún filtro."
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ClipboardItem) -> some View {
        Button("Copiar", systemImage: "doc.on.doc") { copy(item) }

        if !pinboards.pinboards.isEmpty {
            Menu("Añadir a pinboard") {
                ForEach(pinboards.pinboards) { board in
                    Button(board.name) { move(item, to: board.id) }
                }
            }
        }
        if item.pinboardID != nil {
            Button("Quitar del pinboard") { move(item, to: nil) }
        }

        Divider()

        // El deslizamiento ya borraba, pero no se ve: quien viene del Mac busca
        // el borrado donde está en el Mac, en el menú.
        Button("Borrar", systemImage: "trash", role: .destructive) { delete(item) }
    }

    // MARK: - Barra

    private var scopeTitle: String {
        switch model.scope {
        case .history: "Historial"
        case .everything: "Todo"
        case .pinboard(let id):
            pinboards.pinboards.first { $0.id == id }?.name ?? "Pinboard"
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button("Historial") { model.scope = .history }
            Button("Todo") { model.scope = .everything }

            if !pinboards.pinboards.isEmpty {
                Divider()
                ForEach(pinboards.pinboards) { board in
                    Button("\(board.name) (\(pinboards.count(for: board)))") {
                        model.scope = .pinboard(board.id)
                    }
                }
            }

            Divider()
            Button("Gestionar pinboards…", systemImage: "square.stack.3d.up") {
                showingPinboards = true
            }
        } label: {
            Label("Ámbito", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var kindFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ContentKind.filterable, id: \.self) { kind in
                    let on = model.kinds.contains(kind)
                    Button(kind.label) {
                        if on { model.kinds.remove(kind) } else { model.kinds.insert(kind) }
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    // MARK: - Acciones

    /// En iOS no hay Direct Paste (§17): lo máximo es dejarlo en el portapapeles
    /// para que el usuario pegue donde estaba.
    private func copy(_ item: ClipboardItem) {
        guard let text = item.plainText else { return }
        UIPasteboard.general.string = text
    }

    /// Borrado lógico: la fila se queda con `deletedAt` para que el otro
    /// dispositivo se entere en el siguiente ciclo en vez de reenviarla.
    private func delete(_ item: ClipboardItem) {
        try? store.softDelete(id: item.id)
        // El widget lee la misma base, pero no se entera de que ha cambiado.
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func move(_ item: ClipboardItem, to pinboardID: UUID?) {
        try? store.move(id: item.id, toPinboard: pinboardID)
    }

    /// Guarda lo pegado. La política —tipos sensibles, tope de tamaño,
    /// deduplicación— la decide `SharedCapture`, que es el mismo camino que usa
    /// la Share Extension.
    private func capture(_ snapshot: PasteboardSnapshot) {
        try? capture?.capture(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
