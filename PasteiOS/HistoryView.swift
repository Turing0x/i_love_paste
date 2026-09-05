import PasteCore
import SwiftUI
import UIKit
import WidgetKit

/// Pantalla principal: historial, pinboards, búsqueda y filtros.
struct HistoryView: View {
    private let capture: SharedCapture?

    /// Los modelos los posee el `AppEnvironment` y sobreviven a cada apertura:
    /// aquí no se guardan con `@State`.
    ///
    /// `State(initialValue:)` promete una propiedad que esta vista no tiene, e
    /// ignora el valor recibido en cualquier recreación posterior. Con
    /// `@Observable`, para algo de fuera lo que corresponde es leerlo tal cual,
    /// y `@Bindable` cuando además hacen falta enlaces.
    @Bindable private var model: HistoryListViewModel
    private let pinboards: PinboardListViewModel

    /// La sincronización vive en el `AppEnvironment`, pero la vista no lo
    /// necesita entero: le basta con saber si está en marcha y cómo pedirla.
    private let isSyncing: Bool
    private let onSync: () -> Void

    @State private var showingPinboards = false
    @State private var showingClearConfirmation = false

    init(
        capture: SharedCapture?,
        model: HistoryListViewModel,
        pinboards: PinboardListViewModel,
        isSyncing: Bool,
        onSync: @escaping () -> Void
    ) {
        self.capture = capture
        self._model = Bindable(model)
        self.pinboards = pinboards
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
                    // Solo dentro de un pinboard el orden es del usuario; en el
                    // historial no hay nada que reordenar (§104-108 del modelo).
                    if model.allowsManualOrder {
                        ToolbarItem(placement: .topBarLeading) { EditButton() }
                    }
                    ToolbarItem(placement: .topBarTrailing) { syncButton }
                    ToolbarItem(placement: .topBarTrailing) { PasteButton(onCapture: capture) }
                }
                .searchable(text: $model.query, prompt: "Buscar en el historial")
                .safeAreaInset(edge: .top) { kindFilters }
                .sheet(isPresented: $showingPinboards) {
                    PinboardsView(model: pinboards) { deletedID in
                        // La lista no puede quedarse apuntando a un pinboard que
                        // ya no existe: se vería vacía sin explicación. El aviso
                        // al widget lo da el propio modelo al borrar.
                        if model.scope == .pinboard(deletedID) { model.scope = .history }
                    }
                }
                .confirmationDialog(
                    "¿Vaciar el historial?",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Vaciar historial", role: .destructive) { clearHistory() }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Se borrarán los elementos sueltos. Lo que esté en un pinboard se conserva.")
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
                HStack(spacing: 12) {
                    // El toque para copiar se queda solo sobre el contenido: si
                    // envolviera toda la fila se dispararía también al pulsar
                    // los botones de la derecha.
                    ItemRow(item: item)
                        .contentShape(.rect)
                        .onTapGesture { copy(item) }

                    pinboardButton(for: item)
                    deleteButton(for: item)
                }
                .contextMenu { menu(for: item) }
            }
            // `nil` esconde el asa de arrastre: en historial el orden lo pone
            // la fecha, no el dedo.
            .onMove(perform: model.allowsManualOrder ? { self.moveItems(from: $0, to: $1) } : nil)
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

    // MARK: - Acciones de la fila

    /// Borrar, a la vista.
    ///
    /// Sustituye al deslizamiento: una acción que no se ve no existe para quien
    /// no sabe que está ahí.
    private func deleteButton(for item: ClipboardItem) -> some View {
        Button {
            delete(item)
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
                // 44×44 es el mínimo de las guías de interfaz humana. Con 32 el
                // botón se acierta a la primera con un dedo fino y a la tercera
                // con cualquier otro.
                .frame(minWidth: Self.tapTarget, minHeight: Self.tapTarget)
                .contentShape(.rect)
        }
        // Sin `.plain` el `List` trata cualquier toque de la fila como pulsación
        // de todos sus botones.
        .buttonStyle(.plain)
        // Un botón que solo es un símbolo no tiene nombre para VoiceOver: sin
        // esto se anuncia como "botón" a secas, y hay dos seguidos.
        .accessibilityLabel("Borrar")
        .accessibilityHint(item.displayTitle)
    }

    /// Añadir a un pinboard, o sacarlo del que esté.
    ///
    /// No se muestra si no hay pinboards y el elemento no está en ninguno: sería
    /// un menú vacío.
    @ViewBuilder
    private func pinboardButton(for item: ClipboardItem) -> some View {
        let pinned = item.pinboardID != nil

        if pinned || !pinboards.pinboards.isEmpty {
            Menu {
                if !pinboards.pinboards.isEmpty {
                    ForEach(pinboards.pinboards) { board in
                        Button(board.name) { move(item, to: board.id) }
                    }
                }
                if pinned {
                    Divider()
                    Button("Quitar del pinboard") { move(item, to: nil) }
                }
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(minWidth: Self.tapTarget, minHeight: Self.tapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // El estado "está en un pinboard" solo lo dice el relleno del icono:
            // en la etiqueta tiene que ir con palabras.
            .accessibilityLabel(pinned ? "En un pinboard" : "Añadir a un pinboard")
            .accessibilityHint(item.displayTitle)
        }
    }

    /// Mínimo táctil de las guías de interfaz humana.
    private static let tapTarget: CGFloat = 44

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

            Divider()

            // La retención automática tarda 30 días; esto es para cuando se
            // quiere el historial limpio ahora.
            Button("Vaciar historial", systemImage: "trash", role: .destructive) {
                showingClearConfirmation = true
            }
        } label: {
            Label("Ámbito", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Cambiar de lista")
        .accessibilityValue(scopeTitle)
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
                    // Activo y desactivado se distinguen solo por el tinte, que
                    // no existe para VoiceOver ni para quien no separa esos dos
                    // colores.
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityLabel("Filtrar por \(kind.label)")
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
    ///
    /// Va por el modelo, que es quien recoge el fallo y quien avisa al widget.
    /// Repartido por la vista, el aviso se olvidaba en cuanto aparecía un
    /// camino de escritura nuevo.
    private func delete(_ item: ClipboardItem) {
        model.delete(id: item.id)
    }

    private func move(_ item: ClipboardItem, to pinboardID: UUID?) {
        model.move(id: item.id, toPinboard: pinboardID)
    }

    /// Puente entre el índice que da `List` al arrastrar y el orden fraccional
    /// que entiende el view model.
    private func moveItems(from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first else { return }
        model.move(model.items[source], before: destination)
    }

    /// Vacía el historial suelto. Los pinboards no se tocan: son justamente lo
    /// que el usuario ha decidido conservar.
    private func clearHistory() {
        model.clearHistory()
    }

    /// Guarda lo pegado. La política —tipos sensibles, tope de tamaño,
    /// deduplicación— la decide `SharedCapture`, que es el mismo camino que usa
    /// la Share Extension.
    private func capture(_ snapshot: PasteboardSnapshot) {
        // Si se está viendo un pinboard, lo pegado va a ese pinboard: cayendo en
        // el historial suelto desaparecería de la lista en el acto y parecería
        // que no se ha guardado.
        var destination: UUID?
        if case .pinboard(let id) = model.scope { destination = id }

        try? capture?.capture(snapshot, pinboardID: destination)
        // El único camino de escritura que no pasa por el modelo: la política de
        // captura vive en `SharedCapture`, que es el mismo por el que entra la
        // Share Extension. De ahí que el aviso al widget siga aquí a mano.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
