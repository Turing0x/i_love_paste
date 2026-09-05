import Foundation
import Testing
@testable import PasteCore

/// Cuatro filas con orden 1, 2, 3, 4 y un identificador reconocible.
private let a = UUID()
private let b = UUID()
private let c = UUID()
private let d = UUID()

private let rows: [(id: UUID, sortOrder: Double)] = [
    (a, 1), (b, 2), (c, 3), (d, 4)
]

@Test func arrastrarHaciaAbajoCaeDelanteDeLaFilaDondeSeSuelta() {
    // Este es el fallo que había: soltar B sobre D lo mandaba detrás de D.
    let spot = ReorderPlan.neighbours(moving: b, before: 3, in: rows)
    #expect(spot == ReorderPlan.Neighbours(after: 3, before: 4))
}

@Test func arrastrarHaciaArribaCaeDelanteDeLaFilaDondeSeSuelta() {
    let spot = ReorderPlan.neighbours(moving: d, before: 1, in: rows)
    #expect(spot == ReorderPlan.Neighbours(after: 1, before: 2))
}

@Test func soltarAlFinalDejaAlUltimoDetras() {
    let spot = ReorderPlan.neighbours(moving: a, before: nil, in: rows)
    #expect(spot == ReorderPlan.Neighbours(after: 4, before: nil))
}

@Test func soltarAlPrincipioDejaAlPrimeroDelante() {
    let spot = ReorderPlan.neighbours(moving: d, before: 0, in: rows)
    #expect(spot == ReorderPlan.Neighbours(after: nil, before: 1))
}

@Test func soltarUnElementoSobreSiMismoNoLoMueve() {
    // Ni hacia su propia posición ni hacia la siguiente: en los dos casos se
    // queda entre los mismos vecinos que ya tenía.
    #expect(
        ReorderPlan.neighbours(moving: b, before: 1, in: rows)
            == ReorderPlan.Neighbours(after: 1, before: 3)
    )
    #expect(
        ReorderPlan.neighbours(moving: b, before: 2, in: rows)
            == ReorderPlan.Neighbours(after: 1, before: 3)
    )
}

@Test func unIndiceMasAllaDelFinalSeSujetaAlFinal() {
    let spot = ReorderPlan.neighbours(moving: a, before: 99, in: rows)
    #expect(spot == ReorderPlan.Neighbours(after: 4, before: nil))
}

@Test func unaListaDeUnSoloElementoNoTieneVecinos() {
    #expect(ReorderPlan.neighbours(moving: a, before: nil, in: [(a, 1)]) == nil)
}

@Test func unElementoQueNoEstaEnLaListaNoSeMueve() {
    #expect(ReorderPlan.neighbours(moving: UUID(), before: 1, in: rows) == nil)
}

// MARK: - El orden que sale de aplicar el plan

/// Reordena de verdad usando el mismo cálculo fraccional que el store, para
/// comprobar la secuencia resultante y no solo los vecinos.
private func reordered(moving id: UUID, before index: Int?) -> [UUID] {
    guard let spot = ReorderPlan.neighbours(moving: id, before: index, in: rows) else {
        return rows.map(\.id)
    }
    let order = ClipboardStore.fractionalOrder(after: spot.after, before: spot.before)
    return rows
        .map { $0.id == id ? (id: $0.id, sortOrder: order) : $0 }
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(\.id)
}

@Test func elOrdenResultanteHaciaAbajoEsElEsperado() {
    #expect(reordered(moving: b, before: 3) == [a, c, b, d])
}

@Test func elOrdenResultanteHaciaArribaEsElEsperado() {
    #expect(reordered(moving: d, before: 1) == [a, d, b, c])
}

@Test func elOrdenResultanteAlFinalEsElEsperado() {
    #expect(reordered(moving: a, before: nil) == [b, c, d, a])
}
