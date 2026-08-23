import Foundation
import GRDB
import Testing
@testable import PasteCore

private let deviceLocal = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
private let deviceRemoto = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!

private func makeStore() throws -> ClipboardStore {
    ClipboardStore(try AppDatabase.inMemory())
}

private func item(
    id: UUID = UUID(),
    _ text: String,
    device: UUID = deviceRemoto,
    createdAt: Date = Date(timeIntervalSince1970: 1000),
    updatedAt: Date = Date(timeIntervalSince1970: 1000),
    deletedAt: Date? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: id,
        contentHash: ContentHasher.hash(text: text),
        kind: .text,
        plainText: text,
        byteSize: text.utf8.count,
        sourceDeviceID: device,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt
    )
}

@Test func unElementoRemotoNuevoEntraYNoSeReencola() throws {
    let store = try makeStore()
    let remoto = item("del otro dispositivo")

    let resubir = try store.applyRemote(RemoteBatch(items: [remoto]))

    #expect(resubir.isEmpty)
    #expect(try store.items(matching: .history).map(\.id) == [remoto.id])
    #expect(try store.pendingChanges().isEmpty)
}

@Test func siLoLocalEsMasNuevoNoSePisaYSePideResubirlo() throws {
    let store = try makeStore()
    let local = try store.capture(item("versión buena", updatedAt: Date(timeIntervalSince1970: 5000)))
    try store.clearPending(recordNames: [local.id.uuidString])

    let viejo = item(id: local.id, "versión vieja", updatedAt: Date(timeIntervalSince1970: 1000))
    let resubir = try store.applyRemote(RemoteBatch(items: [viejo]))

    #expect(resubir == [local.id.uuidString])
    #expect(try store.item(id: local.id)?.plainText == "versión buena")
}

@Test func unPinboardRemotoLlegaAntesQueSuElemento() throws {
    let store = try makeStore()
    let board = Pinboard(name: "Trabajo")
    var enBoard = item("firma")
    enBoard.pinboardID = board.id

    // Mismo lote: los pinboards se aplican primero.
    try store.applyRemote(RemoteBatch(items: [enBoard], pinboards: [board]))
    #expect(try store.items(matching: HistoryFilter(scope: .pinboard(board.id))).count == 1)

    // Y en lotes separados, con el elemento por delante: es el caso que motivó
    // soltar la clave ajena.
    let otroBoard = UUID()
    var huerfano = item("llega antes que su pinboard")
    huerfano.pinboardID = otroBoard
    try store.applyRemote(RemoteBatch(items: [huerfano]))
    #expect(try store.item(id: huerfano.id)?.pinboardID == otroBoard)

    try store.applyRemote(RemoteBatch(pinboards: [Pinboard(id: otroBoard, name: "Después")]))
    #expect(try store.items(matching: HistoryFilter(scope: .pinboard(otroBoard))).count == 1)
}

@Test func elMismoTextoCopiadoEnLosDosDispositivosConvergeAUnaFila() throws {
    let store = try makeStore()
    // Copiado aquí sin red.
    let local = try store.capture(item(
        id: UUID(uuidString: "11111111-0000-0000-0000-000000000000")!,
        "mismo texto",
        device: deviceLocal,
        createdAt: Date(timeIntervalSince1970: 1000)
    ))
    // Y copiado allí, con otro id y el mismo contenido.
    let remoto = item(
        id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
        "mismo texto",
        createdAt: Date(timeIntervalSince1970: 2000),
        updatedAt: Date(timeIntervalSince1970: 2000)
    )

    let resubir = try store.applyRemote(RemoteBatch(items: [remoto]))

    // El índice único es parcial sobre los vivos: solo puede quedar uno.
    let vivos = try store.items(matching: .history)
    #expect(vivos.map(\.id) == [local.id])
    #expect(vivos.first?.createdAt == Date(timeIntervalSince1970: 2000))

    // La lápida del perdedor tiene que subir, o el otro dispositivo nunca se
    // entera de que su fila dejó de existir.
    #expect(Set(resubir) == [local.id.uuidString, remoto.id.uuidString])
    #expect(try store.item(id: remoto.id)?.deletedAt != nil)
}

@Test func unBorradoFisicoDelServidorQuitaLaFilaYSusMetadatos() throws {
    let store = try makeStore()
    let local = try store.capture(item("efímero"))
    try store.setRecordSystemFields(Data([1]), for: local.id.uuidString, in: .clipboardItem)

    try store.applyRemote(RemoteBatch(deletedRecordNames: [local.id.uuidString]))

    #expect(try store.item(id: local.id) == nil)
    #expect(try store.recordSystemFields(for: local.id.uuidString) == nil)
    #expect(try store.pendingChanges().isEmpty)
}

@Test func aplicarUnLoteNoDejaLaColaSucia() throws {
    let store = try makeStore()
    let board = Pinboard(name: "Trabajo")
    let uno = item("uno")
    let dos = item("dos")

    try store.applyRemote(RemoteBatch(items: [uno, dos], pinboards: [board]))

    // Si la cola no queda vacía hay bucle de eco: lo que baja vuelve a subir.
    #expect(try store.pendingChanges().isEmpty)
}
