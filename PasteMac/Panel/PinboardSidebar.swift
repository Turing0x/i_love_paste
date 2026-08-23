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
    @FocusState private var nameFocused: Bool

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

    private func fixedScope(_ target: HistoryFilter.Scope, title: String, symbol: String) -> some View {
        let isSelected = scope == target
        return Label(title, systemImage: symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowStyle(isSelected: isSelected)
            .contentShape(.rect)
            .onTapGesture { scope = target }
            // Soltar sobre "Historial" saca el elemento de su pinboard, que es
            // el camino de vuelta natural del arrastre.
            .dropDestination(for: ItemTransfer.self) { transfers, _ in
                guard target == .history, let first = transfers.first else { return false }
                moveItem(first.id, nil)
                return true
            }
    }

    @ViewBuilder
    private func pinboardRow(_ board: Pinboard, index: Int) -> some View {
        let isSelected = scope == .pinboard(board.id)

        HStack(spacing: 8) {
            Circle()
                .fill(PinboardColor.color(hex: board.colorHex))
                .frame(width: 9, height: 9)

            if renamingID == board.id {
                TextField("Nombre", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit { commitRename(board) }
                    // Esc cancela sin dejar que la tecla siga subiendo: arriba
                    // hay un `onKeyPress` que escondería el panel entero.
                    .onExitCommand { renamingID = nil }
            } else {
                Text(board.name).lineLimit(1)
                Spacer(minLength: 4)
                if model.count(for: board) > 0 {
                    Text("\(model.count(for: board))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle(isSelected: isSelected)
        .contentShape(.rect)
        .onTapGesture { scope = .pinboard(board.id) }
        .contextMenu { menu(for: board) }
        .draggable(PinboardTransfer(id: board.id))
        .dropDestination(for: ItemTransfer.self) { transfers, _ in
            guard let first = transfers.first else { return false }
            moveItem(first.id, board.id)
            return true
        }
        .dropDestination(for: PinboardTransfer.self) { transfers, _ in
            guard let first = transfers.first,
                  let dragged = model.pinboards.first(where: { $0.id == first.id })
            else { return false }
            model.move(dragged, before: index)
            return true
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
        nameFocused = true
    }

    private func commitRename(_ board: Pinboard) {
        model.rename(board, to: draftName)
        renamingID = nil
    }
}

private extension View {
    /// Fondo y color de una fila de la barra lateral, iguales a los de la lista.
    func rowStyle(isSelected: Bool) -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : .clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
