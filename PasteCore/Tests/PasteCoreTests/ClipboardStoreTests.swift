import Foundation
import GRDB
import Testing
@testable import PasteCore

private let device = UUID()

private func makeStore() throws -> ClipboardStore {
    ClipboardStore(try AppDatabase.inMemory())
}

private func textItem(
    _ text: String,
    app: String? = "com.apple.Safari",
    appName: String? = "Safari",
    at date: Date = Date()
) -> ClipboardItem {
    ClipboardItem(
        contentHash: ContentHasher.hash(text: text),
        kind: .text,
        plainText: text,
        byteSize: text.utf8.count,
        sourceBundleID: app,
        sourceAppName: appName,
        sourceDeviceID: device,
        createdAt: date,
        updatedAt: date
    )
}

// MARK: - Esquema

@Test func migracionCreaTablasEIndiceFTS() throws {
    let db = try AppDatabase.inMemory()
    try db.reader.read { db in
        try #expect(db.tableExists("clipboardItem"))
        try #expect(db.tableExists("pinboard"))
        try #expect(db.tableExists("device"))
        try #expect(db.tableExists("clipboardItem_fts"))
    }
}

// MARK: - Deduplicación

@Test func capturarDosVecesElMismoTextoNoDuplicaFila() throws {
    let store = try makeStore()
    let t0 = Date(timeIntervalSince1970: 1000)
    let t1 = Date(timeIntervalSince1970: 2000)

    let primero = try store.capture(textItem("git rebase -i", at: t0))
    let segundo = try store.capture(textItem("git rebase -i", at: t1))

    #expect(primero.id == segundo.id)
    try #expect(store.items(limit: 100).count == 1)
}

@Test func recopiarAsciendeElElementoALoMasReciente() throws {
    let store = try makeStore()
    try store.capture(textItem("viejo", at: Date(timeIntervalSince1970: 1000)))
    try store.capture(textItem("nuevo", at: Date(timeIntervalSince1970: 2000)))
    // Se vuelve a copiar el viejo: debe pasar al principio.
    try store.capture(textItem("viejo", at: Date(timeIntervalSince1970: 3000)))

    let items = try store.items(limit: 10)
    #expect(items.map(\.plainText) == ["viejo", "nuevo"])
}

@Test func recopiarRefrescaLaAppDeOrigen() throws {
    let store = try makeStore()
    try store.capture(textItem("token", app: "com.apple.Safari", appName: "Safari"))
    try store.capture(textItem("token", app: "com.microsoft.VSCode", appName: "Code"))

    let items = try store.items(limit: 10)
    #expect(items.count == 1)
    #expect(items[0].sourceAppName == "Code")
}

@Test func elIndiceUnicoDeHashIgnoraLasLapidas() throws {
    let store = try makeStore()
    let original = try store.capture(textItem("secreto"))
    try store.softDelete(id: original.id)

    // Volver a copiar algo ya borrado debe crear un elemento nuevo, no chocar
    // con la lápida ni resucitarla.
    let recapturado = try store.capture(textItem("secreto"))
    #expect(recapturado.id != original.id)
    try #expect(store.items(limit: 10).count == 1)
}

@Test func hashesDistintosParaTextoYBinarioConLosMismosBytes() throws {
    let texto = "hola"
    #expect(ContentHasher.hash(text: texto) != ContentHasher.hash(data: Data(texto.utf8)))
}

@Test func elHashNormalizaSaltosDeLineaYEspaciosDeLosExtremos() throws {
    #expect(ContentHasher.hash(text: "a\r\nb") == ContentHasher.hash(text: "a\nb"))
    #expect(ContentHasher.hash(text: "  hola  ") == ContentHasher.hash(text: "hola"))
    // Pero las mayúsculas y los espacios interiores sí distinguen: en código importan.
    #expect(ContentHasher.hash(text: "Hola") != ContentHasher.hash(text: "hola"))
    #expect(ContentHasher.hash(text: "a  b") != ContentHasher.hash(text: "a b"))
}

// MARK: - Borrado y edición

@Test func elBorradoEsLogicoYDejaLaFila() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("adios"))
    try store.softDelete(id: item.id)

    try #expect(store.items(limit: 10).isEmpty)
    // La fila sigue ahí, marcada: es lo que impide que la sincronización la resucite.
    let persistido = try store.item(id: item.id)
    #expect(persistido?.deletedAt != nil)
}

@Test func renombrarCambiaElTituloMostrado() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("https://api.example.com/v1/auth"))
    try store.rename(id: item.id, to: "Endpoint de autenticación")

    try #expect(store.item(id: item.id)?.displayTitle == "Endpoint de autenticación")
    try store.rename(id: item.id, to: nil)
    try #expect(store.item(id: item.id)?.displayTitle == "https://api.example.com/v1/auth")
}

@Test func editarElTextoRecalculaElHash() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("borrador"))
    let hashOriginal = item.contentHash

    try store.updateText(id: item.id, to: "definitivo")
    let editado = try store.item(id: item.id)
    #expect(editado?.plainText == "definitivo")
    #expect(editado?.contentHash != hashOriginal)

    // Y al recalcularse, volver a copiar el texto original crea un elemento
    // aparte en vez de sobrescribir el editado.
    try store.capture(textItem("borrador"))
    try #expect(store.items(limit: 10).count == 2)
}

// MARK: - Búsqueda

@Test func laBusquedaEncuentraPorContenido() throws {
    let store = try makeStore()
    try store.capture(textItem("flutter pub get"))
    try store.capture(textItem("swift build"))

    let resultados = try store.search("flutter")
    #expect(resultados.count == 1)
    #expect(resultados[0].plainText == "flutter pub get")
}

@Test func laBusquedaIgnoraLosAcentos() throws {
    let store = try makeStore()
    try store.capture(textItem("revisar el código de producción"))

    try #expect(store.search("codigo").count == 1)
    try #expect(store.search("código").count == 1)
}

@Test func laBusquedaCoincidePorPrefijo() throws {
    let store = try makeStore()
    try store.capture(textItem("autenticación con tokens"))

    // Buscar mientras escribes: "auten" ya debe encontrarlo.
    try #expect(store.search("auten").count == 1)
}

@Test func laBusquedaEncuentraPorTituloManual() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("xK9$mZ2p"))
    try store.rename(id: item.id, to: "clave del servidor")

    try #expect(store.search("servidor").count == 1)
}

@Test func laBusquedaEncuentraPorHostDeUrl() throws {
    let store = try makeStore()
    let url = "https://github.com/groue/GRDB.swift"
    try store.capture(ClipboardItem(
        contentHash: ContentHasher.hash(text: url),
        kind: .url,
        plainText: url,
        sourceDeviceID: device
    ))

    try #expect(store.search("github").count == 1)
}

@Test func laBusquedaVaciaDevuelveElListadoNormal() throws {
    let store = try makeStore()
    try store.capture(textItem("uno"))
    try store.capture(textItem("dos"))

    // Un espacio no debe vaciar la pantalla.
    try #expect(store.search("   ").count == 2)
    try #expect(store.search("").count == 2)
}

@Test func laBusquedaNoDevuelveElementosBorrados() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("flutter pub get"))
    try store.softDelete(id: item.id)

    try #expect(store.search("flutter").isEmpty)
}

@Test func laBusquedaRespetaElFiltroDeTipo() throws {
    let store = try makeStore()
    try store.capture(textItem("informe anual"))
    try store.capture(ClipboardItem(
        contentHash: ContentHasher.hash(text: "informe.pdf"),
        kind: .file,
        plainText: "informe.pdf",
        blobPath: "ab/cdef",
        sourceDeviceID: device
    ))

    let soloFicheros = HistoryFilter(kinds: [.file])
    let resultados = try store.search("informe", matching: soloFicheros)
    #expect(resultados.count == 1)
    #expect(resultados[0].kind == .file)
}

// MARK: - Filtros

@Test func elFiltroPorAppDeOrigenRestringeElListado() throws {
    let store = try makeStore()
    try store.capture(textItem("a", app: "com.apple.Safari", appName: "Safari"))
    try store.capture(textItem("b", app: "com.microsoft.VSCode", appName: "Code"))

    let soloCode = HistoryFilter(bundleIDs: ["com.microsoft.VSCode"])
    try #expect(store.items(matching: soloCode).map(\.plainText) == ["b"])
}

@Test func elFiltroPorFechaRestringeElListado() throws {
    let store = try makeStore()
    try store.capture(textItem("viejo", at: Date(timeIntervalSince1970: 1000)))
    try store.capture(textItem("nuevo", at: Date(timeIntervalSince1970: 5000)))

    let recientes = HistoryFilter(createdAfter: Date(timeIntervalSince1970: 3000))
    try #expect(store.items(matching: recientes).map(\.plainText) == ["nuevo"])
}

@Test func elListadoDeAppsDeOrigenCuentaSoloElementosVivos() throws {
    let store = try makeStore()
    try store.capture(textItem("a", app: "com.apple.Safari", appName: "Safari"))
    try store.capture(textItem("b", app: "com.apple.Safari", appName: "Safari"))
    let borrado = try store.capture(textItem("c", app: "com.microsoft.VSCode", appName: "Code"))
    try store.softDelete(id: borrado.id)

    let apps = try store.sourceApps()
    #expect(apps.count == 1)
    #expect(apps[0].bundleID == "com.apple.Safari")
    #expect(apps[0].count == 2)
}

// MARK: - Pinboards

@Test func moverAUnPinboardLoSacaDelHistorial() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("plantilla de email"))
    let board = Pinboard(name: "Trabajo")
    try store.save(board)

    try store.move(id: item.id, toPinboard: board.id)

    try #expect(store.items(matching: .history).isEmpty)
    try #expect(store.items(matching: HistoryFilter(scope: .pinboard(board.id))).count == 1)
    try #expect(store.items(matching: HistoryFilter(scope: .everything)).count == 1)
}

@Test func devolverAlHistorialQuitaElPinboard() throws {
    let store = try makeStore()
    let item = try store.capture(textItem("nota"))
    let board = Pinboard(name: "Trabajo")
    try store.save(board)

    try store.move(id: item.id, toPinboard: board.id)
    try store.move(id: item.id, toPinboard: nil)

    try #expect(store.items(matching: .history).count == 1)
    try #expect(store.item(id: item.id)?.pinboardID == nil)
}

@Test func reordenarUsaOrdenFraccionalYSoloTocaLaFilaMovida() throws {
    let store = try makeStore()
    let board = Pinboard(name: "Snippets")
    try store.save(board)

    var ids: [UUID] = []
    for texto in ["a", "b", "c"] {
        let item = try store.capture(textItem(texto))
        try store.move(id: item.id, toPinboard: board.id)
        ids.append(item.id)
    }

    let scope = HistoryFilter(scope: .pinboard(board.id))
    let antes = try store.items(matching: scope)
    #expect(antes.map(\.plainText) == ["a", "b", "c"])

    // Mover "c" entre "a" y "b".
    try store.reorder(id: ids[2], after: antes[0].sortOrder, before: antes[1].sortOrder)

    let despues = try store.items(matching: scope)
    #expect(despues.map(\.plainText) == ["a", "c", "b"])
    // "a" y "b" conservan su orden original: no se reescribió la lista entera.
    #expect(despues[0].sortOrder == antes[0].sortOrder)
    #expect(despues[2].sortOrder == antes[1].sortOrder)
}

// MARK: - Retención

@Test func laRetencionPorAntiguedadNoTocaLosPinboards() throws {
    let store = try makeStore()
    let ahora = Date(timeIntervalSince1970: 100_000)
    let viejo = Date(timeIntervalSince1970: 1000)

    let suelto = try store.capture(textItem("efímero", at: viejo))
    let guardado = try store.capture(textItem("permanente", at: viejo))
    let board = Pinboard(name: "Trabajo")
    try store.save(board)
    try store.move(id: guardado.id, toPinboard: board.id)

    let purgados = try store.applyRetention(maxAge: 3600, maxItems: nil, now: ahora)

    #expect(purgados == 1)
    try #expect(store.item(id: suelto.id)?.deletedAt != nil)
    // La razón de existir de un pinboard es que su contenido no caduca.
    try #expect(store.item(id: guardado.id)?.deletedAt == nil)
}

@Test func laRetencionPorCantidadConservaLosMasRecientes() throws {
    let store = try makeStore()
    for i in 0..<5 {
        try store.capture(textItem("item \(i)", at: Date(timeIntervalSince1970: Double(i) * 1000)))
    }

    try store.applyRetention(maxAge: nil, maxItems: 2)

    let quedan = try store.items(limit: 10)
    #expect(quedan.map(\.plainText) == ["item 4", "item 3"])
}

@Test func purgarLapidasDevuelveLosBlobsHuerfanos() throws {
    let store = try makeStore()
    let item = ClipboardItem(
        contentHash: ContentHasher.hash(data: Data([1, 2, 3])),
        kind: .image,
        blobPath: "ab/cdef",
        sourceDeviceID: device
    )
    try store.capture(item)
    try store.softDelete(id: item.id, at: Date(timeIntervalSince1970: 1000))

    let huerfanos = try store.purgeTombstones(olderThan: Date(timeIntervalSince1970: 5000))

    #expect(huerfanos == ["ab/cdef"])
    try #expect(store.item(id: item.id) == nil)
}

@Test func purgarLapidasNoBorraBlobsQueSiguenEnUso() throws {
    let store = try makeStore()
    let hash = ContentHasher.hash(data: Data([1, 2, 3]))

    let vivo = ClipboardItem(
        contentHash: hash + ".vivo",
        kind: .image,
        blobPath: "ab/cdef",
        sourceDeviceID: device
    )
    let muerto = ClipboardItem(
        contentHash: hash + ".muerto",
        kind: .image,
        blobPath: "ab/cdef",
        sourceDeviceID: device
    )
    try store.capture(vivo)
    try store.capture(muerto)
    try store.softDelete(id: muerto.id, at: Date(timeIntervalSince1970: 1000))

    let huerfanos = try store.purgeTombstones(olderThan: Date(timeIntervalSince1970: 5000))

    // El blob lo sigue referenciando `vivo`: borrarlo dejaría un elemento roto.
    #expect(huerfanos.isEmpty)
}

// MARK: - Blobs

@Test func elBlobStoreRepartePorPrefijoYQuitaElPrefijoDeTipo() throws {
    #expect(BlobStore.relativePath(for: "b:abcdef1234") == "ab/abcdef1234")
}

@Test func elBlobStoreNoReescribeUnBlobQueYaExiste() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = BlobStore(root: root)
    let datos = Data([1, 2, 3, 4])
    let hash = ContentHasher.hash(data: datos)

    let ruta = try store.store(datos, hash: hash)
    let fecha = try FileManager.default
        .attributesOfItem(atPath: store.url(for: ruta).path)[.modificationDate] as? Date

    let rutaRepetida = try store.store(datos, hash: hash)
    let fechaDespues = try FileManager.default
        .attributesOfItem(atPath: store.url(for: ruta).path)[.modificationDate] as? Date

    #expect(ruta == rutaRepetida)
    #expect(fecha == fechaDespues)
    try #expect(store.data(at: ruta) == datos)
}

// MARK: - Dispositivos

@Test func registrarElMismoDispositivoDosVecesNoDuplica() throws {
    let store = try makeStore()
    let id = UUID()
    try store.registerDevice(Device(id: id, name: "MacBook", platform: .macOS))
    try store.registerDevice(Device(id: id, name: "MacBook de Raúl", platform: .macOS))

    let devices = try store.devices()
    #expect(devices.count == 1)
    #expect(devices[0].name == "MacBook de Raúl")
}

// MARK: - Observación en vivo

@Test func laObservacionEmiteAlCapturar() async throws {
    let store = try makeStore()
    var iterator = store.observeItems().makeAsyncIterator()

    // La primera emisión es el estado actual: vacío.
    let inicial = try await iterator.next()
    #expect(inicial?.isEmpty == true)

    try store.capture(textItem("recién copiado"))

    let despues = try await iterator.next()
    #expect(despues?.map(\.plainText) == ["recién copiado"])
}
