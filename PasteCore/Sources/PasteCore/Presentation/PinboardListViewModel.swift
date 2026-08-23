import Foundation

/// Estado de la barra lateral: los pinboards vivos y cuántos elementos tiene
/// cada uno.
///
/// Va aparte de `HistoryListViewModel` porque observa otra cosa y a otro ritmo:
/// la lista cambia con cada copia, la barra lateral solo cuando el usuario
/// organiza.
@MainActor
@Observable
public final class PinboardListViewModel {
    private let store: ClipboardStore

    public private(set) var pinboards: [Pinboard] = []
    public private(set) var counts: [UUID: Int] = [:]
    public private(set) var error: String?

    private var observation: Task<Void, Never>?
    private var countsObservation: Task<Void, Never>?

    public init(store: ClipboardStore) {
        self.store = store
    }

    public func start() {
        observation?.cancel()
        observation = Task { [weak self] in
            guard let self else { return }
            do {
                for try await fresh in store.observePinboards() {
                    guard !Task.isCancelled else { return }
                    self.pinboards = fresh
                    self.error = nil
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = String(describing: error)
            }
        }

        // Las cuentas van por su cuenta y no colgadas de la lista: mover un
        // elemento a un pinboard escribe en `clipboardItem`, así que la lista no
        // emite y el contador se quedaba viejo justo después de un arrastre.
        countsObservation?.cancel()
        countsObservation = Task { [weak self] in
            guard let self else { return }
            do {
                for try await fresh in store.observePinboardCounts() {
                    guard !Task.isCancelled else { return }
                    self.counts = fresh
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        countsObservation?.cancel()
        countsObservation = nil
    }

    public func count(for pinboard: Pinboard) -> Int {
        counts[pinboard.id] ?? 0
    }

    // MARK: - Escritura

    @discardableResult
    public func create(name: String) -> Pinboard? {
        perform { try store.createPinboard(name: name) }
    }

    public func rename(_ pinboard: Pinboard, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un pinboard sin nombre sería una fila en blanco imposible de volver a
        // seleccionar: el nombre vacío se descarta y se queda el anterior.
        guard !clean.isEmpty, clean != pinboard.name else { return }
        perform { try store.updatePinboard(id: pinboard.id, name: clean) }
    }

    public func setColor(_ hex: String, on pinboard: Pinboard) {
        perform { try store.updatePinboard(id: pinboard.id, colorHex: hex) }
    }

    public func delete(_ pinboard: Pinboard) {
        perform { try store.deletePinboard(id: pinboard.id) }
    }

    /// Recoloca un pinboard delante del que ocupa `index`, o al final con `nil`.
    public func move(_ pinboard: Pinboard, before index: Int?) {
        // El propio elemento arrastrado no cuenta como vecino: si lo fuera,
        // soltarlo sobre sí mismo lo mandaría a un hueco que no existe.
        let others = pinboards.filter { $0.id != pinboard.id }
        let target = index.map { min($0, others.count) } ?? others.count

        let after = target > 0 ? others[target - 1].sortOrder : nil
        let before = target < others.count ? others[target].sortOrder : nil
        guard after != nil || before != nil else { return }

        perform { try store.reorderPinboard(id: pinboard.id, after: after, before: before) }
    }

    /// Las escrituras no lanzan hacia la vista: un fallo se enseña, no revienta
    /// el panel a media organización.
    @discardableResult
    private func perform<T>(_ work: () throws -> T) -> T? {
        do {
            return try work()
        } catch {
            self.error = String(describing: error)
            return nil
        }
    }
}
