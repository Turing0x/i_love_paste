import Foundation
import Testing
@testable import PasteCore

@Test func elCursorSeMueveArribaYAbajo() {
    let cursor = SelectionCursor()
    #expect(cursor.moved(by: 1, count: 5).index == 1)
    #expect(cursor.moved(by: 1, count: 5).moved(by: 1, count: 5).index == 2)
    #expect(SelectionCursor(index: 3).moved(by: -1, count: 5).index == 2)
}

@Test func elCursorSeParaAlFinalSinDarLaVuelta() {
    // Mantener pulsada la flecha abajo debe quedarse en el último, no reaparecer
    // arriba.
    let cursor = SelectionCursor(index: 4)
    #expect(cursor.moved(by: 1, count: 5).index == 4)
    #expect(cursor.moved(by: 10, count: 5).index == 4)
}

@Test func elCursorSeParaAlPrincipioSinDarLaVuelta() {
    let cursor = SelectionCursor(index: 0)
    #expect(cursor.moved(by: -1, count: 5).index == 0)
    #expect(cursor.moved(by: -10, count: 5).index == 0)
}

@Test func conListaVaciaElCursorEsCero() {
    #expect(SelectionCursor(index: 7).moved(by: 1, count: 0).index == 0)
    #expect(SelectionCursor(index: 7).clamped(to: 0).index == 0)
}

@Test func alEncogerLaListaElCursorSeRecoloca() {
    // Es lo que pasa al escribir en el buscador: veinte resultados pasan a tres
    // y el índice se queda fuera de rango.
    #expect(SelectionCursor(index: 19).clamped(to: 3).index == 2)
    // Si sigue cabiendo, no se toca.
    #expect(SelectionCursor(index: 1).clamped(to: 3).index == 1)
}

@Test func elCursorNuncaEsNegativo() {
    #expect(SelectionCursor(index: -5).index == 0)
}

@Test func elCursorDevuelveElElementoSeleccionado() {
    let items = ["a", "b", "c"]
    #expect(SelectionCursor(index: 1).selected(in: items) == "b")
    #expect(SelectionCursor(index: 9).selected(in: items) == nil)
    #expect(SelectionCursor().selected(in: [String]()) == nil)
}

// MARK: - Rangos de fecha

@Test func elRangoCualquierFechaNoRestringe() {
    let filtro = DateRangePreset.any.applied(to: .history)
    #expect(filtro.createdAfter == nil)
}

@Test func elRangoHoyEmpiezaAlComienzoDelDia() {
    var calendario = Calendar(identifier: .gregorian)
    calendario.timeZone = TimeZone(identifier: "Europe/Madrid")!
    let ahora = calendario.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 15))!

    let filtro = DateRangePreset.today.applied(to: .history, now: ahora, calendar: calendario)

    // A las tres de la tarde, "hoy" no debe arrastrar lo de ayer.
    #expect(filtro.createdAfter == calendario.startOfDay(for: ahora))
}

@Test func losRangosDeDiasRestanDesdeAhora() {
    let calendario = Calendar(identifier: .gregorian)
    let ahora = Date(timeIntervalSince1970: 1_000_000)

    let siete = DateRangePreset.last7Days.applied(to: .history, now: ahora, calendar: calendario)
    let treinta = DateRangePreset.last30Days.applied(to: .history, now: ahora, calendar: calendario)

    #expect(siete.createdAfter == calendario.date(byAdding: .day, value: -7, to: ahora))
    #expect(treinta.createdAfter == calendario.date(byAdding: .day, value: -30, to: ahora))
}

@Test func elRangoConservaElRestoDelFiltro() {
    let original = HistoryFilter(
        scope: .everything,
        kinds: [.url],
        bundleIDs: ["com.apple.Safari"]
    )
    let filtrado = DateRangePreset.today.applied(to: original)

    #expect(filtrado.scope == .everything)
    #expect(filtrado.kinds == [.url])
    #expect(filtrado.bundleIDs == ["com.apple.Safari"])
}
