import PasteCore
import SwiftUI

/// Contenido del panel flotante: buscador, filtros y lista.
struct PanelView: View {
    let environment: AppEnvironment
    @State private var model: HistoryListViewModel
    @State private var pinboards: PinboardListViewModel
    @FocusState private var searchFocused: Bool

    init(
        environment: AppEnvironment,
        model: HistoryListViewModel,
        pinboards: PinboardListViewModel
    ) {
        self.environment = environment
        self._model = State(initialValue: model)
        self._pinboards = State(initialValue: pinboards)
    }

    var body: some View {
        HStack(spacing: 0) {
            PinboardSidebar(
                model: pinboards,
                scope: $model.scope,
                moveItem: move
            )
            Divider()
            VStack(spacing: 0) {
                searchField
                Divider()
                filterBar
                Divider()
                list
            }
        }
        .background(.regularMaterial)
        .onAppear {
            // El modelo sobrevive entre aperturas, así que hay que limpiarlo a
            // mano: el panel se abre muchas veces al día y encontrarse la
            // búsqueda de la vez anterior desconcierta.
            model.reset()
            model.start()
            pinboards.start()
            searchFocused = true
        }
        .onDisappear {
            model.stop()
            pinboards.stop()
        }
        // Las teclas se interceptan aquí arriba para que el campo de búsqueda,
        // que conserva el foco todo el rato, no se quede con las flechas.
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        // ⇧↩ pega el elemento seleccionado sin formato (§18, modo individual).
        .onKeyPress(keys: [.return]) { press in
            activateSelection(asPlainText: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(.escape) { environment.panel.hide(); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            guard press.modifiers.contains(.command),
                  let number = Int(press.characters), number > 0,
                  let item = model.item(atQuickPasteNumber: number)
            else { return .ignored }
            use(item, asPlainText: press.modifiers.contains(.shift))
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar en el historial", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .onSubmit { activateSelection() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ContentKind.filterable, id: \.self) { kind in
                Toggle(kind.label, isOn: Binding(
                    get: { model.kinds.contains(kind) },
                    set: { on in
                        if on { model.kinds.insert(kind) } else { model.kinds.remove(kind) }
                    }
                ))
                .toggleStyle(.button)
                .buttonStyle(.accessoryBar)
                .controlSize(.small)
            }

            Spacer()

            Picker("", selection: $model.bundleID) {
                Text("Todas las apps").tag(String?.none)
                ForEach(model.sourceApps, id: \.bundleID) { app in
                    Text("\(app.name) (\(app.count))").tag(String?.some(app.bundleID))
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 170)

            Picker("", selection: $model.datePreset) {
                ForEach(DateRangePreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            icon: item.sourceBundleID.flatMap {
                                environment.icons.icon(forBundleID: $0)
                            },
                            quickPasteNumber: index < HistoryListViewModel.quickPasteCount
                                ? index + 1
                                : nil,
                            isSelected: index == model.cursor.index
                        )
                        .id(item.id)
                        .onTapGesture { use(item) }
                        .contextMenu { menu(for: item) }
                        .draggable(ItemTransfer(id: item.id))
                        // Reordenar solo tiene sentido dentro de un pinboard:
                        // en el historial el orden es la fecha.
                        .dropDestination(for: ItemTransfer.self) { transfers, _ in
                            guard model.allowsManualOrder,
                                  let first = transfers.first,
                                  let dragged = model.items.first(where: { $0.id == first.id })
                            else { return false }
                            model.move(dragged, before: index)
                            return true
                        }
                    }
                }
                .padding(6)
            }
            // Navegar con el teclado hasta un elemento fuera de pantalla no
            // sirve de nada si la vista no lo sigue.
            .onChange(of: model.cursor) {
                if let selected = model.selectedItem {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "Historial vacío" : "Sin resultados",
                    systemImage: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                    description: Text(
                        model.query.isEmpty
                            ? "Copia algo y aparecerá aquí."
                            : "Prueba con otra búsqueda o quita algún filtro."
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ClipboardItem) -> some View {
        Button("Pegar") { use(item) }
        Button("Pegar como texto plano") { use(item, asPlainText: true) }

        Divider()

        // El menú duplica lo que hace el arrastre a propósito: es el camino
        // descubrible, y el único accesible desde el teclado.
        if !pinboards.pinboards.isEmpty {
            Menu("Añadir a pinboard") {
                ForEach(pinboards.pinboards) { board in
                    Button(board.name) { move(item.id, to: board.id) }
                }
            }
        }
        if item.pinboardID != nil {
            Button("Quitar del pinboard") { move(item.id, to: nil) }
        }

        Divider()

        Button("Borrar", role: .destructive) {
            try? environment.store?.softDelete(id: item.id)
        }
    }

    /// Mueve un elemento a un pinboard, o lo devuelve al historial con `nil`.
    private func move(_ id: UUID, to pinboardID: UUID?) {
        try? environment.store?.move(id: id, toPinboard: pinboardID)
    }

    private func activateSelection(asPlainText: Bool = false) {
        guard let item = model.selectedItem else { return }
        use(item, asPlainText: asPlainText)
    }

    /// Deja el elemento en el portapapeles, cierra el panel y lo pega en la app
    /// que estaba delante. Sin permiso de Accesibilidad solo copia.
    private func use(_ item: ClipboardItem, asPlainText: Bool = false) {
        environment.use(item, asPlainText: asPlainText)
    }
}
