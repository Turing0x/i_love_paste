import PasteCore
import SwiftUI

/// Columna izquierda del panel: ámbitos fijos y pinboards del usuario.
///
/// Existe además del menú contextual porque el arrastre necesita un destino
/// visible: sin los pinboards en pantalla no hay dónde soltar (§21).
struct PinboardSidebar: View {
    let model: PinboardListViewModel
    @Binding var scope: HistoryFilter.Scope

    /// Mueve un elemento a un pinboard, o al historial con `nil`.
    let moveItem: (UUID, UUID?) -> Void

    /// Pinboard en edición de nombre. El renombrado es inline y no una hoja: el
    /// panel se cierra al perder el foco, así que cualquier ventana aparte se lo
    /// llevaría por delante.
    @State private var renamingID: UUID?
    @State private var draftName = ""

    /// Foco por identidad y no por un booleano: la fila del pinboard recién
    /// creado todavía no existe cuando se pide el foco —`model.pinboards` se
    /// llena cuando emite la observación, que es asíncrona—, así que un `Bool`
    /// puesto en ese momento no se lo lleva nadie.
    @FocusState private var focusedBoard: UUID?

    /// Fila resaltada por un arrastre encima. Sin realimentación, un arrastre
    /// que no funciona es indistinguible de uno que sí.
    @State private var dropTargetID: UUID?
    @State private var historyIsTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    fixedScope(.history, title: "Historial", symbol: "clock")
                    fixedScope(.everything, title: "Todo", symbol: "tray.full")

                    Divider().padding(.vertical, 6)

                    ForEach(Array(model.pinboards.enumerated()), id: \.element.id) { index, board in
                        pinboardRow(board, index: index)
                    }
                }
                .padding(6)
            }

            Divider()
            newPinboardButton
        }
        .frame(width: 170)
        .background(.quaternary.opacity(0.25))
    }

    // MARK: - Filas

    @ViewBuilder
    private func fixedScope(_ target: HistoryFilter.Scope, title: String, symbol: String) -> some View {
        let isSelected = scope == target
        let row = Label(title, systemImage: symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowStyle(
                isSelected: isSelected,
                isDropTarget: target == .history && historyIsTargeted
            )
            .contentShape(.rect)
            .onTapGesture { scope = target }

        // Soltar sobre "Historial" saca el elemento de su pinboard, que es el
        // camino de vuelta natural del arrastre. "Todo" no acepta nada: antes
        // llevaba el mismo modificador y enseñaba un cursor que mentía.
        if target == .history {
            row.dropDestination(for: SidebarDrop.self) { drops, _ in
                guard let first = drops.first, case .item(let id) = first else { return false }
                moveItem(id, nil)
                return true
            } isTargeted: { historyIsTargeted = $0 }
        } else {
            row
        }
    }

    @ViewBuilder
    private func pinboardRow(_ board: Pinboard, index: Int) -> some View {
        if renamingID == board.id {
            renameRow(board)
        } else {
            normalRow(board, index: index)
        }
    }

    /// Fila en reposo: seleccionable, arrastrable y destino de soltado.
    private func normalRow(_ board: Pinboard, index: Int) -> some View {
        let isSelected = scope == .pinboard(board.id)

        return HStack(spacing: 8) {
            Circle()
                .fill(PinboardColor.color(hex: board.colorHex))
                .frame(width: 9, height: 9)

            Text(board.name).lineLimit(1)
            Spacer(minLength: 4)
            if model.count(for: board) > 0 {
                Text("\(model.count(for: board))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle(isSelected: isSelected, isDropTarget: dropTargetID == board.id)
        .contentShape(.rect)
        .onTapGesture { scope = .pinboard(board.id) }
        .contextMenu { menu(for: board) }
        .draggable(PinboardTransfer(id: board.id))
        // Un solo destino de soltado: una vista admite uno, y con dos apilados
        // el segundo tapaba al primero sin decir nada.
        .dropDestination(for: SidebarDrop.self) { drops, _ in
            guard let first = drops.first else { return false }
            switch first {
            case .item(let id):
                moveItem(id, board.id)
                return true
            case .pinboard(let id):
                guard let dragged = model.pinboards.first(where: { $0.id == id }) else { return false }
                model.move(dragged, before: index)
                return true
            }
        } isTargeted: { targeted in
            if targeted {
                dropTargetID = board.id
            } else if dropTargetID == board.id {
                dropTargetID = nil
            }
        }
    }

    /// Fila en edición de nombre.
    ///
    /// Sin `onTapGesture` ni `draggable` encima a propósito: el campo necesita el
    /// clic para colocar el cursor, y con la fila capturándolo no había forma de
    /// escribir ni de salir del renombrado.
    private func renameRow(_ board: Pinboard) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PinboardColor.color(hex: board.colorHex))
                .frame(width: 9, height: 9)

            TextField("Nombre", text: $draftName)
                .textFieldStyle(.plain)
                .focused($focusedBoard, equals: board.id)
                .onSubmit { commitRename(board) }
                // Esc cancela sin dejar que la tecla siga subiendo: arriba
                // hay un `onKeyPress` que escondería el panel entero.
                .onExitCommand { cancelRename() }
                // Lo mismo con las flechas: el panel las intercepta para mover
                // la selección de la lista, y renombrando son del campo.
                .onKeyPress(.upArrow) { .handled }
                .onKeyPress(.downArrow) { .handled }
                .onAppear {
                    // El campo nace después de que `startRename` pidiera el
                    // foco, así que hay que volver a pedirlo cuando ya existe
                    // alguien a quien dárselo.
                    focusedBoard = board.id
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle(isSelected: scope == .pinboard(board.id))
        // Perder el foco confirma, como en el Finder. Sin esto, hacer clic en
        // otro sitio dejaba la fila convertida en un campo de texto para
        // siempre y el pinboard recién creado se quedaba llamándose "Nuevo
        // pinboard".
        .onChange(of: focusedBoard) { previous, current in
            guard previous == board.id, current != board.id, renamingID == board.id
            else { return }
            commitRename(board)
        }
        // Red de seguridad: pulsar fuera esconde el panel entero
        // (`windowDidResignKey`) y ahí puede no quedar ciclo de foco que
        // observar. Es idempotente: las otras salidas ya dejaron `renamingID`
        // en `nil`.
        .onDisappear {
            guard renamingID == board.id else { return }
            commitRename(board)
        }
    }

    @ViewBuilder
    private func menu(for board: Pinboard) -> some View {
        Button("Renombrar") { startRename(board) }

        Menu("Color") {
            ForEach(PinboardColor.palette, id: \.hex) { entry in
                Button(entry.name) { model.setColor(entry.hex, on: board) }
            }
        }

        Divider()

        Button("Borrar pinboard", role: .destructive) {
            // Sus elementos vuelven al historial, no se van con él: eso lo
            // resuelve `deletePinboard` en el store.
            if scope == .pinboard(board.id) { scope = .history }
            model.delete(board)
        }
    }

    private var newPinboardButton: some View {
        Button {
            guard let board = model.create(name: "Nuevo pinboard") else { return }
            // Se crea con nombre provisional y se entra a renombrar en el acto:
            // pedir el nombre antes exigiría un diálogo, y un diálogo cierra
            // este panel.
            scope = .pinboard(board.id)
            startRename(board)
        } label: {
            Label("Nuevo pinboard", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.secondary)
    }

    // MARK: - Renombrado

    private func startRename(_ board: Pinboard) {
        draftName = board.name
        renamingID = board.id
        // El `onAppear` del campo lo vuelve a pedir: la fila puede no existir
        // todavía, y entonces esto no llega a ninguna parte.
        focusedBoard = board.id
    }

    private func commitRename(_ board: Pinboard) {
        model.rename(board, to: draftName)
        endRename()
    }

    /// Esc deja el nombre anterior. Sale antes de soltar el foco para que el
    /// `onChange` no lo confunda con un clic fuera y lo guarde igualmente.
    private func cancelRename() {
        endRename()
    }

    private func endRename() {
        renamingID = nil
        focusedBoard = nil
    }
}

private extension View {
    /// Fondo y color de una fila de la barra lateral, iguales a los de la lista.
    func rowStyle(isSelected: Bool, isDropTarget: Bool = false) -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : .clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
    }
}
