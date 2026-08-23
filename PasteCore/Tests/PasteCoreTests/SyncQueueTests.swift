import Foundation
import GRDB
import Testing
@testable import PasteCore

private let device = UUID()

private func makeStore() throws -> ClipboardStore {
    ClipboardStore(try AppDatabase.inMemory())
}

private func textItem(_ text: String, at date: Date = Date()) -> ClipboardItem {
    ClipboardItem(
        contentHash: ContentHasher.hash(text: text),
        kind: .text,
        plainText: text,
        byteSize: text.utf8.count,
        sourceDeviceID: device,
        createdAt: date,
        updatedAt: date
    )
}

@Test func laMigracionCreaLasTablasDeSincronizacion() throws {
    let db = try AppDatabase.inMemory()
    try db.reader.read { db in
        try #expect(db.tableExists("ckRecordMetadata"))
        try #expect(db.tableExists("pendingSyncChange"))
        try #expect(db.tableExists("syncEngineState"))
    }
}

@Test func laMigracionV2ConservaLosDatosYSueltaLaClaveAjena() throws {
    let queue = try DatabaseQueue()
    try AppDatabase.migrator.migrate(queue, upTo: "v1.schema")

    let board = Pinboard(name: "Trabajo")
    let guardado = textItem("firma")
    try queue.write { db in
        try board.insert(db)
        var enBoard = guardado
        enBoard.pinboardID = board.id
        try enBoard.insert(db)
    }

    try AppDatabase.migrator.migrate(queue)
    let store = ClipboardStore(try AppDatabase(queue))

    // La reconstrucción de la tabla no puede perder el historial del usuario.
    #expect(try store.item(id: guardado.id)?.pinboardID == board.id)
    // Ni el índice de búsqueda, que se repuebla al rehacerse.
    #expect(try store.search("firma", matching: HistoryFilter(scope: .everything))
        .map(\.id) == [guardado.id])

    // Y lo que motivó soltar la clave ajena: un elemento puede llegar antes que
    // el pinboard al que pertenece, porque el servidor no promete que vengan en
    // el mismo lote.
    var huerfano = textItem("llega antes que su pinboard")
    huerfano.pinboardID = UUID()
    try queue.write { db in try huerfano.insert(db) }
    #expect(try store.item(id: huerfano.id) != nil)
}

@Test func capturarEncolaElElemento() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("hola"))

    let pending = try store.pendingChanges()
    #expect(pending.map(\.recordName) == [item.id.uuidString])
    #expect(pending.first?.tableName == .clipboardItem)
}

@Test func tocarLaMismaFilaVariasVecesDejaUnaSolaEntrada() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("hola"))
    try store.rename(id: item.id, to: "saludo")
    try store.softDelete(id: item.id)

    // La clave primaria es el registro: diez cambios son una subida, no diez.
    #expect(try store.pendingChanges().count == 1)
}

@Test func losPinboardsYLosDispositivosTambienSeEncolan() throws {
    let store = try makeStore()
    let board = try store.createPinboard(name: "Trabajo")
    try store.registerDevice(Device(id: device, name: "Mac", platform: .macOS))

    let porTabla = try Dictionary(
        grouping: store.pendingChanges(),
        by: \.tableName
    ).mapValues(\.count)

    #expect(porTabla[.pinboard] == 1)
    #expect(porTabla[.device] == 1)
    #expect(try store.pendingChanges().contains { $0.recordName == board.id.uuidString })
}

@Test func desencolarQuitaSoloLoIndicado() throws {
    let store = try makeStore()
    let uno = try store.capture(textItem("uno"))
    let dos = try store.capture(textItem("dos"))

    try store.clearPending(recordNames: [uno.id.uuidString])

    #expect(try store.pendingChanges().map(\.recordName) == [dos.id.uuidString])
}

@Test func aplicarUnCambioRemotoNoLoReencola() throws {
    let store = try makeStore()
    let remoto = textItem("llegado del servidor")

    try store.applyingRemote(recordNames: [remoto.id.uuidString]) { db in
        try remoto.insert(db)
    }

    // Si esto falla hay bucle de eco: lo aplicado desde el servidor se sube otra
    // vez, y de ahí a subir y bajar lo mismo indefinidamente.
    #expect(try store.pendingChanges().isEmpty)
    #expect(try store.item(id: remoto.id) != nil)
}

@Test func purgarLapidasNoEncolaBorradosFisicos() throws {
    let store = try makeStore()
    let viejo = Date(timeIntervalSince1970: 1000)
    let item = try store.capture(textItem("efímero", at: viejo))
    try store.softDelete(id: item.id, at: viejo)
    try store.clearPending(recordNames: [item.id.uuidString])

    _ = try store.purgeTombstones(olderThan: Date(timeIntervalSince1970: 100_000))

    // La lápida ya viajó cuando se purga: encolar el borrado físico haría subir
    // un registro que el servidor ya no tiene por qué volver a ver.
    #expect(try store.pendingChanges().isEmpty)
}

@Test func elEstadoDelMotorSobreviveYSeSobrescribe() throws {
    let store = try makeStore()
    #expect(try store.syncEngineState() == nil)

    try store.setSyncEngineState(Data([1, 2, 3]))
    #expect(try store.syncEngineState() == Data([1, 2, 3]))

    try store.setSyncEngineState(Data([4]))
    #expect(try store.syncEngineState() == Data([4]))
}

@Test func losCamposDeSistemaSeGuardanPorRegistro() throws {
    let store = try makeStore()
    let name = UUID().uuidString

    #expect(try store.recordSystemFields(for: name) == nil)
    try store.setRecordSystemFields(Data([9]), for: name, in: .clipboardItem)
    #expect(try store.recordSystemFields(for: name) == Data([9]))
}
