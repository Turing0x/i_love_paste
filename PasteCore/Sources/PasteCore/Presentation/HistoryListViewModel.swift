import Foundation
import GRDB

/// Estado de la lista del panel: consulta, filtros, resultados y selección.
@MainActor
@Observable
public final class HistoryListViewModel {
    private let store: ClipboardStore

    /// Ámbito visible: el historial suelto, un pinboard, o todo junto.
    public var scope: HistoryFilter.Scope = .history {
        didSet {
            restartIfNeeded(oldValue)
            onScopeChange?(scope)
        }
    }

    /// Avisa de cualquier cambio de ámbito, venga de donde venga (tocar un
    /// pinboard, un deep link del widget…), para que quien lo escuche pueda
    /// persistirlo como "última posición abierta".
    public var onScopeChange: ((HistoryFilter.Scope) -> Void)?

    /// Avisa de que una escritura ha salido de aquí.
    ///
    /// Lo escucha el iPhone para pedirle al widget que se refresque: lee la
    /// misma base pero no la observa, así que si nadie se lo dice se queda
    /// enseñando lo de antes. Es un aviso y no una llamada a WidgetKit porque
    /// el Mac no tiene widget, y `PasteCore` no tiene por qué saber cuál de las
    /// dos apps lo está usando.
    ///
    /// Antes esto lo hacía cada vista después de cada escritura, repetido en
    /// seis sitios: el primero que escribiera desde un séptimo se olvidaría.
    public var onLocalChange: (() -> Void)?
    public var query: String = "" { didSet { restartIfNeeded(oldValue) } }
    public var kinds: Set<ContentKind> = [] { didSet { restartIfNeeded(oldValue) } }
    public var bundleID: String? { didSet { restartIfNeeded(oldValue) } }
    public var datePreset: DateRangePreset = .any { didSet { restartIfNeeded(oldValue) } }

    public private(set) var items: [ClipboardItem] = []
    public private(set) var sourceApps: [(bundleID: String, name: String, count: Int)] = []
    public private(set) var error: String?

    public var cursor = SelectionCursor()

    private var observation: Task<Void, Never>?

    /// Los nueve primeros son alcanzables con ⌘1–9.
    public static let quickPasteCount = 9

    public init(store: ClipboardStore) {
        self.store = store
    }

    public var selectedItem: ClipboardItem? { cursor.selected(in: items) }

    public func moveSelection(by delta: Int) {
        cursor = cursor.moved(by: delta, count: items.count)
    }

    /// Elemento en la posición de un atajo ⌘N, contando desde 1.
    public func item(atQuickPasteNumber number: Int) -> ClipboardItem? {
        let index = number - 1
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    public func start() {
        refreshSourceApps()
        restart()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    /// Deja la búsqueda como estaba al abrir: el panel se usa muchas veces al
    /// día y arrastrar el filtro de la vez anterior sorprende.
    ///
    /// El ámbito (`scope`) no se toca aquí: quién lo restaura es cosa de la
    /// persistencia de "última posición abierta" de cada plataforma, no de un
    /// reseteo genérico.
    public func reset() {
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
    public var allowsManualOrder: Bool {
        if case .pinboard = scope { return true }
        return false
    }

    /// Recoloca un elemento delante del que ocupa `index` **en la lista
    /// visible**, o al final con `nil`.
    ///
    /// El cálculo de los vecinos vive en `ReorderPlan`: es el mismo para los
    /// pinboards y es lo que hay que probar, no el camino hasta el store.
    public func move(_ item: ClipboardItem, before index: Int?) {
        guard allowsManualOrder else { return }

        let rows = items.map { (id: $0.id, sortOrder: $0.sortOrder) }
        guard let spot = ReorderPlan.neighbours(moving: item.id, before: index, in: rows)
        else { return }

        perform { try store.reorder(id: item.id, after: spot.after, before: spot.before) }
    }

    // MARK: - Escritura

    /// Borra un elemento. Lógico, como todo borrado aquí.
    public func delete(id: UUID) {
        perform { try store.softDelete(id: id) }
    }

    /// Mueve un elemento a un pinboard, o lo devuelve al historial con `nil`.
    public func move(id: UUID, toPinboard pinboardID: UUID?) {
        perform { try store.move(id: id, toPinboard: pinboardID) }
    }

    /// Vacía el historial suelto. Los pinboards no se tocan.
    public func clearHistory() {
        perform { try store.softDeleteHistory() }
    }

    /// Las escrituras pasan todas por aquí.
    ///
    /// Es lo que garantiza dos cosas que antes dependían de que la vista se
    /// acordase: que un fallo quede recogido en `error` en vez de perderse en un
    /// `try?`, y que quien escuche `onLocalChange` se entere.
    @discardableResult
    private func perform<T>(_ work: () throws -> T) -> T? {
        do {
            let result = try work()
            onLocalChange?()
            return result
        } catch {
            self.error = String(describing: error)
            return nil
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
