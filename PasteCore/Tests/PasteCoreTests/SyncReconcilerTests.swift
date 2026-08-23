import Foundation
import Testing
@testable import PasteCore

private let deviceA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
private let deviceB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!

private func item(
    id: UUID = UUID(),
    _ text: String,
    device: UUID = deviceA,
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

// MARK: - Último en escribir gana

@Test func sinFilaLocalGanaElRemoto() {
    #expect(SyncReconciler.resolve(local: nil as ClipboardItem?, remote: item("hola")) == .remote)
}

@Test func elMasRecienteGana() {
    let id = UUID()
    let viejo = item(id: id, "viejo", updatedAt: Date(timeIntervalSince1970: 1000))
    let nuevo = item(id: id, "nuevo", updatedAt: Date(timeIntervalSince1970: 2000))

    #expect(SyncReconciler.resolve(local: viejo, remote: nuevo) == .remote)
    #expect(SyncReconciler.resolve(local: nuevo, remote: viejo) == .local)
}

@Test func laLapidaNoEsUnCasoEspecial() {
    let id = UUID()
    let vivo = item(id: id, "texto", updatedAt: Date(timeIntervalSince1970: 1000))
    let borrado = item(
        id: id,
        "texto",
        updatedAt: Date(timeIntervalSince1970: 2000),
        deletedAt: Date(timeIntervalSince1970: 2000)
    )

    // Borrar mueve `updatedAt`, así que compite con la regla normal.
    #expect(SyncReconciler.resolve(local: vivo, remote: borrado) == .remote)
    #expect(SyncReconciler.resolve(local: borrado, remote: vivo) == .local)
}

@Test func elEmpateSeResuelveIgualDesdeLosDosLados() {
    let id = UUID()
    let momento = Date(timeIntervalSince1970: 1000)
    let uno = item(id: id, "uno", device: deviceA, updatedAt: momento)
    let otro = item(id: id, "otro", device: deviceB, updatedAt: momento)

    // Cada dispositivo llama "remoto" a la versión del otro. Si el empate lo
    // ganase siempre el remoto, se intercambiarían la fila indefinidamente: aquí
    // los dos tienen que quedarse con el mismo contenido.
    let desdeUno = SyncReconciler.resolve(local: uno, remote: otro)
    let desdeOtro = SyncReconciler.resolve(local: otro, remote: uno)

    let ganadorSegunUno = desdeUno == .remote ? otro : uno
    let ganadorSegunOtro = desdeOtro == .remote ? uno : otro
    #expect(ganadorSegunUno.id == ganadorSegunOtro.id)
    #expect(ganadorSegunUno.syncFingerprint == ganadorSegunOtro.syncFingerprint)
}

@Test func elEmpateConContenidoIdenticoNoCambiaNada() {
    let id = UUID()
    let momento = Date(timeIntervalSince1970: 1000)
    let local = item(id: id, "texto", updatedAt: momento)
    let remoto = item(id: id, "texto", updatedAt: momento)

    #expect(SyncReconciler.resolve(local: local, remote: remoto) == .local)
}

@Test func losPinboardsUsanLaMismaRegla() {
    let id = UUID()
    let viejo = Pinboard(id: id, name: "Trabajo", updatedAt: Date(timeIntervalSince1970: 1000))
    let nuevo = Pinboard(id: id, name: "Curro", updatedAt: Date(timeIntervalSince1970: 2000))

    #expect(SyncReconciler.resolve(local: viejo, remote: nuevo) == .remote)
    #expect(SyncReconciler.resolve(local: nuevo, remote: viejo) == .local)
}

@Test func losDispositivosDesempatanPorLastSeenAt() {
    let id = UUID()
    let viejo = Device(id: id, name: "Mac", platform: .macOS, lastSeenAt: Date(timeIntervalSince1970: 1000))
    let nuevo = Device(id: id, name: "Mac de Raúl", platform: .macOS, lastSeenAt: Date(timeIntervalSince1970: 2000))

    #expect(SyncReconciler.resolve(local: viejo, remote: nuevo) == .remote)
}

// MARK: - Colisión de contentHash

@Test func elDuplicadoConservaElIdMenorYLaCopiaMasReciente() {
    let menor = item(
        id: UUID(uuidString: "11111111-0000-0000-0000-000000000000")!,
        "mismo texto",
        createdAt: Date(timeIntervalSince1970: 1000)
    )
    let mayor = item(
        id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
        "mismo texto",
        createdAt: Date(timeIntervalSince1970: 2000)
    )
    let ahora = Date(timeIntervalSince1970: 3000)

    let (winner, loser) = SyncReconciler.resolveDuplicate(menor, mayor, at: ahora)

    #expect(winner.id == menor.id)
    // La fecha más reciente es la que devuelve el elemento a la cabeza de la
    // lista, igual que hace `capture` al ascender un duplicado.
    #expect(winner.createdAt == Date(timeIntervalSince1970: 2000))
    #expect(winner.deletedAt == nil)

    // El perdedor recibe lápida en vez de desaparecer, para que el dispositivo
    // que lo creó se entere de que dejó de existir.
    #expect(loser.id == mayor.id)
    #expect(loser.deletedAt == ahora)
}

@Test func elDuplicadoConvergeEnElMismoResultadoEnLosDosSentidos() {
    let uno = item(
        id: UUID(uuidString: "11111111-0000-0000-0000-000000000000")!,
        "mismo texto",
        createdAt: Date(timeIntervalSince1970: 1000)
    )
    let otro = item(
        id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
        "mismo texto",
        createdAt: Date(timeIntervalSince1970: 2000)
    )
    let ahora = Date(timeIntervalSince1970: 3000)

    let desdeUno = SyncReconciler.resolveDuplicate(uno, otro, at: ahora)
    let desdeOtro = SyncReconciler.resolveDuplicate(otro, uno, at: ahora)

    // Los dos dispositivos resuelven la colisión por separado y sin hablarse.
    #expect(desdeUno.winner == desdeOtro.winner)
    #expect(desdeUno.loser == desdeOtro.loser)
}
