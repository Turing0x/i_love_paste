import Foundation
import PasteCore

/// Estado de la lista del panel: consulta, filtros, resultados y selección.
@MainActor
@Observable
final class HistoryListViewModel {
    private let store: ClipboardStore

    /// Ámbito visible: el historial suelto, un pinboard, o todo junto.
    var scope: HistoryFilter.Scope = .history { didSet { restartIfNeeded(oldValue) } }
    var query: String = "" { didSet { restartIfNeeded(oldValue) } }
    var kinds: Set<ContentKind> = [] { didSet { restartIfNeeded(oldValue) } }
    var bundleID: String? { didSet { restartIfNeeded(oldValue) } }
    var datePreset: DateRangePreset = .any { didSet { restartIfNeeded(oldValue) } }

    private(set) var items: [ClipboardItem] = []
    private(set) var sourceApps: [(bundleID: String, name: String, count: Int)] = []
    private(set) var error: String?

    var cursor = SelectionCursor()

    private var observation: Task<Void, Never>?

    /// Los nueve primeros son alcanzables con ⌘1–9.
    static let quickPasteCount = 9

    init(store: ClipboardStore) {
        self.store = store
    }

    var selectedItem: ClipboardItem? { cursor.selected(in: items) }

    func moveSelection(by delta: Int) {
        cursor = cursor.moved(by: delta, count: items.count)
    }

    /// Elemento en la posición de un atajo ⌘N, contando desde 1.
    func item(atQuickPasteNumber number: Int) -> ClipboardItem? {
        let index = number - 1
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    func start() {
        refreshSourceApps()
        restart()
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }

    /// Deja la búsqueda como estaba al abrir: el panel se usa muchas veces al
    /// día y arrastrar el filtro de la vez anterior sorprende.
    func reset() {
        scope = .history
        query = ""
        kinds = []
        bundleID = nil
        datePreset = .any
        cursor = SelectionCursor()
    }

    private func restartIfNeeded(_ oldValue: some Equatable) {
        restart()
    }

    private func restart() {
        observation?.cancel()

        var filter = HistoryFilter(
            scope: scope,
            kinds: kinds,
            bundleIDs: bundleID.map { [$0] } ?? []
        )
        filter = datePreset.applied(to: filter)

        let query = query
        observation = Task { [weak self] in
            // Cada pulsación levantaría una observación nueva. Amortiguarlas
            // evita crear y destruir varias por palabra escrita.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }

            do {
                for try await fresh in store.observeItems(query: query, matching: filter) {
                    guard !Task.isCancelled else { return }
                    self.items = fresh
                    // La lista se rehace bajo los pies mientras se escribe: la
                    // selección tiene que volver a caer dentro.
                    self.cursor = self.cursor.clamped(to: fresh.count)
                    self.error = nil
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    /// Dentro de un pinboard el orden lo pone el usuario; en el historial lo
    /// pone la fecha y no es negociable.
    var allowsManualOrder: Bool {
        if case .pinboard = scope { return true }
        return false
    }

    /// Recoloca un elemento delante del que ocupa `index`, o al final con `nil`.
    func move(_ item: ClipboardItem, before index: Int?) {
        guard allowsManualOrder else { return }

        // El propio arrastrado no cuenta como vecino: soltarlo sobre sí mismo
        // lo mandaría a un hueco que no existe.
        let others = items.filter { $0.id != item.id }
        let target = index.map { min($0, others.count) } ?? others.count

        let after = target > 0 ? others[target - 1].sortOrder : nil
        let before = target < others.count ? others[target].sortOrder : nil
        guard after != nil || before != nil else { return }

        do {
            try store.reorder(id: item.id, after: after, before: before)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func refreshSourceApps() {
        do {
            sourceApps = try store.sourceApps()
        } catch {
            self.error = String(describing: error)
        }
    }
}
