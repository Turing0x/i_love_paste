import PasteCore
import SwiftUI

/// Contenido del panel flotante: buscador, filtros y lista.
struct PanelView: View {
    let environment: AppEnvironment

    /// Los modelos los posee el `AppEnvironment` y sobreviven a cada apertura:
    /// aquí no se guardan con `@State`.
    ///
    /// `State(initialValue:)` promete una propiedad que esta vista no tiene, e
    /// ignora el valor recibido en cualquier recreación posterior. Con
    /// `@Observable`, para algo de fuera lo que corresponde es leerlo tal cual,
    /// y `@Bindable` cuando además hacen falta enlaces.
    @Bindable private var model: HistoryListViewModel
    private let pinboards: PinboardListViewModel

    @FocusState private var searchFocused: Bool

    init(
        environment: AppEnvironment,
        model: HistoryListViewModel,
        pinboards: PinboardListViewModel
    ) {
        self.environment = environment
        self._model = Bindable(model)
        self.pinboards = pinboards
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
                footer
            }
        }
        .background(.regularMaterial)
        .onAppear {
            // El modelo sobrevive entre aperturas, así que hay que limpiar la
            // búsqueda y los filtros a mano: el panel se abre muchas veces al
            // día y encontrarse los de la vez anterior desconcierta. El
            // ámbito no se toca — ese es justo el que se quiere recordar.
            model.reset()
            model.start()
            pinboards.start()
            searchFocused = true
            // Abrir el panel es justo cuando se espera ver lo que se copió en el
            // iPhone: se fuerza un ciclo en vez de esperar al push silencioso.
            environment.syncNow(force: false)
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

    /// Pie del panel: lo que ha ido mal, o por qué no se guardó lo último.
    ///
    /// Son dos avisos y un solo renglón porque compiten por el mismo hueco y no
    /// pueden ocurrir a la vez de forma interesante: un fallo de escritura es
    /// más urgente que un descarte, que es rutina.
    @ViewBuilder
    private var footer: some View {
        // Los modelos recogen los fallos de escritura en `error` y hasta ahora
        // nadie los pintaba: un borrado que no ocurrió parecía haber ocurrido.
        if let error = model.error ?? pinboards.error {
            Divider()
            note(error, symbol: "exclamationmark.triangle")
        } else if let skip = environment.lastSkipExplanation {
            // "He copiado algo y no aparece" es la pregunta que más se hace de
            // una app así, y hasta ahora la respuesta se calculaba y se tiraba.
            Divider()
            note(skip, symbol: "nosign")
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
                // El campo no lleva etiqueta visible: la lupa de al lado es
                // decorativa y no se lee.
                .accessibilityLabel("Buscar en el historial")
        }
        // La lupa duplica lo que ya dice la etiqueta del campo.
        .accessibilityElement(children: .contain)
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
                .accessibilityLabel("Filtrar por \(kind.label)")
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
            .accessibilityLabel("Filtrar por app de origen")

            Picker("", selection: $model.datePreset) {
                ForEach(DateRangePreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 150)
            .accessibilityLabel("Filtrar por fecha")
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

        Button("Borrar", role: .destructive) { model.delete(id: item.id) }
    }

    /// Mueve un elemento a un pinboard, o lo devuelve al historial con `nil`.
    ///
    /// Pasa por el modelo y no por el store: es el único sitio que recoge el
    /// fallo en vez de tragárselo con un `try?`.
    private func move(_ id: UUID, to pinboardID: UUID?) {
        model.move(id: id, toPinboard: pinboardID)
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
