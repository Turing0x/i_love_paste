import Foundation
import Testing
@testable import PasteCore

/// Espera a que se cumpla una condición sobre el modelo.
///
/// Las observaciones de GRDB emiten de forma asíncrona y `HistoryListViewModel`
/// además amortigua 150 ms cada reinicio, así que no hay ningún punto del que
/// colgarse: se sondea con un techo, que es lo que distingue un test lento de
/// uno colgado.
@MainActor
private func esperar(
    hasta timeout: Duration = .seconds(3),
    _ condition: () -> Bool
) async throws {
    let limite = ContinuousClock.now + timeout
    while ContinuousClock.now < limite {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("La condición no se cumplió en \(timeout)")
}

private func item(_ text: String, pinboardID: UUID? = nil) -> ClipboardItem {
    ClipboardItem(
        contentHash: ContentHasher.hash(text: text),
        kind: .text,
        plainText: text,
        sourceDeviceID: UUID(),
        pinboardID: pinboardID
    )
}

// MARK: - HistoryListViewModel

@MainActor
@Test func elHistorialNoAdmiteOrdenManualYUnPinboardSi() throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let model = HistoryListViewModel(store: store)

    #expect(model.allowsManualOrder == false)
    model.scope = .everything
    #expect(model.allowsManualOrder == false)
    model.scope = .pinboard(UUID())
    #expect(model.allowsManualOrder)
}

@MainActor
@Test func elAvisoDeCambioDeAmbitoLlegaConElNuevoValor() throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let model = HistoryListViewModel(store: store)

    var visto: [HistoryFilter.Scope] = []
    model.onScopeChange = { visto.append($0) }

    let id = UUID()
    model.scope = .pinboard(id)
    model.scope = .history

    #expect(visto == [.pinboard(id), .history])
}

@MainActor
@Test func reiniciarDejaLaBusquedaYLosFiltrosComoAlPrincipioPeroNoElAmbito() throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let model = HistoryListViewModel(store: store)

    let id = UUID()
    model.scope = .pinboard(id)
    model.query = "algo"
    model.kinds = [.url]
    model.bundleID = "com.apple.Safari"
    model.datePreset = .today

    model.reset()

    #expect(model.query.isEmpty)
    #expect(model.kinds.isEmpty)
    #expect(model.bundleID == nil)
    #expect(model.datePreset == .any)
    // El ámbito es justo lo que se quiere recordar entre aperturas.
    #expect(model.scope == .pinboard(id))
}

@MainActor
@Test func elNumeroDeQuickPasteCuentaDesdeUno() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    try store.capture(item("primero"))
    try store.capture(item("segundo"))

    let model = HistoryListViewModel(store: store)
    model.start()
    defer { model.stop() }
    try await esperar { model.items.count == 2 }

    #expect(model.item(atQuickPasteNumber: 1)?.plainText == "segundo")
    #expect(model.item(atQuickPasteNumber: 2)?.plainText == "primero")
    #expect(model.item(atQuickPasteNumber: 0) == nil)
    #expect(model.item(atQuickPasteNumber: 3) == nil)
}

@MainActor
@Test func laSeleccionSeSujetaALosExtremosDeLaLista() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    try store.capture(item("uno"))
    try store.capture(item("dos"))

    let model = HistoryListViewModel(store: store)
    model.start()
    defer { model.stop() }
    try await esperar { model.items.count == 2 }

    model.moveSelection(by: -1)
    #expect(model.cursor.index == 0)
    model.moveSelection(by: 5)
    #expect(model.cursor.index == 1)
    #expect(model.selectedItem?.id == model.items[1].id)
}

@MainActor
@Test func moverDentroDeUnPinboardHaciaAbajoDejaElElementoDondeSeSuelta() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let board = try store.createPinboard(name: "Trabajo")

    // Se crean en orden y se mueven al pinboard, que es lo que les da sortOrder.
    var ids: [UUID] = []
    for texto in ["a", "b", "c", "d"] {
        let guardado = try store.capture(item(texto))
        try store.move(id: guardado.id, toPinboard: board.id)
        ids.append(guardado.id)
    }

    let model = HistoryListViewModel(store: store)
    model.scope = .pinboard(board.id)
    model.start()
    defer { model.stop() }
    try await esperar { model.items.map(\.id) == ids }

    // Soltar «b» sobre «d»: tiene que quedar delante de «d», no detrás.
    model.move(model.items[1], before: 3)
    try await esperar { model.items.map(\.id) == [ids[0], ids[2], ids[1], ids[3]] }
}

@MainActor
@Test func moverEnElHistorialNoHaceNadaPorqueElOrdenEsLaFecha() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    for texto in ["a", "b", "c"] { try store.capture(item(texto)) }

    let model = HistoryListViewModel(store: store)
    model.start()
    defer { model.stop() }
    try await esperar { model.items.count == 3 }

    let antes = model.items.map(\.id)
    model.move(model.items[0], before: 2)
    // Sin espera: `move` sale por el `guard` sin tocar la base.
    #expect(model.items.map(\.id) == antes)
}

// MARK: - PinboardListViewModel

@MainActor
@Test func moverUnPinboardHaciaAbajoLoDejaDondeSeSuelta() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    var ids: [UUID] = []
    for nombre in ["A", "B", "C", "D"] {
        ids.append(try store.createPinboard(name: nombre).id)
    }

    let model = PinboardListViewModel(store: store)
    model.start()
    defer { model.stop() }
    try await esperar { model.pinboards.map(\.id) == ids }

    model.move(model.pinboards[1], before: 3)
    try await esperar { model.pinboards.map(\.id) == [ids[0], ids[2], ids[1], ids[3]] }
}

@MainActor
@Test func renombrarConNombreVacioDejaElAnterior() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let board = try store.createPinboard(name: "Trabajo")

    let model = PinboardListViewModel(store: store)
    model.rename(board, to: "   ")

    #expect(try store.pinboards().first?.name == "Trabajo")
}

@MainActor
@Test func losContadoresIgnoranLosPinboardsVacios() async throws {
    let store = ClipboardStore(try AppDatabase.inMemory())
    let lleno = try store.createPinboard(name: "Lleno")
    let vacio = try store.createPinboard(name: "Vacío")
    let guardado = try store.capture(item("algo"))
    try store.move(id: guardado.id, toPinboard: lleno.id)

    let model = PinboardListViewModel(store: store)
    model.start()
    defer { model.stop() }
    try await esperar { model.counts[lleno.id] == 1 }

    #expect(model.count(for: vacio) == 0)
}

// MARK: - LastScopeStore

@Test func elUltimoAmbitoSobreviveAlCierre() throws {
    let suite = "test.lastScope.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = LastScopeStore(defaults: defaults)
    #expect(store.load() == .history)

    let id = UUID()
    store.save(.pinboard(id))
    #expect(store.load() == .pinboard(id))

    store.save(.everything)
    #expect(store.load() == .everything)
    // Al salir de un pinboard su identificador no se queda por ahí.
    #expect(defaults.string(forKey: "lastScope.pinboardID") == nil)
}
