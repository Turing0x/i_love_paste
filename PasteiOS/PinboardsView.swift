import PasteCore
import SwiftUI

/// Gestión de pinboards en el teléfono: crear, renombrar, color y borrar.
///
/// Gemela de la barra lateral del Mac (`PinboardSidebar`), pero como hoja
/// modal: en un iPhone no hay sitio para una columna permanente, y el menú de
/// ámbito solo sirve para cambiar de lista, no para organizarla.
struct PinboardsView: View {
    @State private var model: PinboardListViewModel

    /// Avisa de qué pinboard se ha borrado para que quien presenta la hoja
    /// pueda soltar el ámbito si estaba dentro de él.
    private let onDeleted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pendingDeletion: Pinboard?
    @State private var renaming: Pinboard?
    @State private var draftName = ""
    @State private var isCreating = false

    init(model: PinboardListViewModel, onDeleted: @escaping (UUID) -> Void) {
        _model = State(initialValue: model)
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Pinboards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Nuevo", systemImage: "plus") { startCreate() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Listo") { dismiss() }
                    }
                }
                .alert("Nuevo pinboard", isPresented: $isCreating) {
                    TextField("Nombre", text: $draftName)
                    Button("Cancelar", role: .cancel) {}
                    Button("Crear") { commitCreate() }
                }
                .alert("Renombrar", isPresented: renamingBinding) {
                    TextField("Nombre", text: $draftName)
                    Button("Cancelar", role: .cancel) {}
                    Button("Guardar") { commitRename() }
                }
                // El borrado sí pregunta: se lleva por delante la organización
                // de muchos elementos de una vez, y en táctil el gesto es fácil
                // de disparar sin querer.
                .confirmationDialog(
                    pendingDeletion.map { "¿Borrar «\($0.name)»?" } ?? "",
                    isPresented: deletionBinding,
                    titleVisibility: .visible
                ) {
                    Button("Borrar pinboard", role: .destructive) { commitDelete() }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Sus elementos no se borran: vuelven al historial.")
                }
        }
        .onAppear { model.start() }
    }

    private var list: some View {
        List {
            ForEach(model.pinboards) { board in
                row(board)
                    .swipeActions(edge: .trailing) {
                        Button("Borrar", role: .destructive) { pendingDeletion = board }
                    }
                    .contextMenu { menu(for: board) }
            }

            // El view model se traga los fallos de escritura; aquí es donde se
            // ven, en vez de dejar que un borrado que no ocurrió parezca que sí.
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.pinboards.isEmpty {
                ContentUnavailableView(
                    "Sin pinboards",
                    systemImage: "square.stack.3d.up",
                    description: Text("Crea uno para guardar lo que quieras conservar.")
                )
            }
        }
    }

    private func row(_ board: Pinboard) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(PinboardColor.color(hex: board.colorHex))
                .frame(width: 10, height: 10)

            Text(board.name).lineLimit(1)
            Spacer(minLength: 4)

            if model.count(for: board) > 0 {
                Text("\(model.count(for: board))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func menu(for board: Pinboard) -> some View {
        Button("Renombrar", systemImage: "pencil") { startRename(board) }

        Menu("Color") {
            ForEach(PinboardColor.palette, id: \.hex) { entry in
                Button(entry.name) { model.setColor(entry.hex, on: board) }
            }
        }

        Divider()

        Button("Borrar pinboard", systemImage: "trash", role: .destructive) {
            pendingDeletion = board
        }
    }

    // MARK: - Acciones

    /// Las alertas se atan a un `Bool`, pero lo que hay que recordar es *qué*
    /// pinboard se está tocando: estos puentes sirven de lo uno a lo otro.
    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private func startCreate() {
        draftName = ""
        isCreating = true
    }

    private func commitCreate() {
        let clean = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.create(name: clean)
    }

    private func startRename(_ board: Pinboard) {
        draftName = board.name
        renaming = board
    }

    private func commitRename() {
        guard let board = renaming else { return }
        // `rename` ya descarta el nombre vacío y el que no cambia.
        model.rename(board, to: draftName)
        renaming = nil
    }

    private func commitDelete() {
        guard let board = pendingDeletion else { return }
        model.delete(board)
        pendingDeletion = nil
        onDeleted(board.id)
    }
}
