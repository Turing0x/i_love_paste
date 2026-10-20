import Foundation
import Testing
@testable import PasteCore

private let dia: TimeInterval = 24 * 3600
private let caducidad = Date(timeIntervalSince1970: 1_000_000)

private func derecho(
    level: EntitlementLevel = .paid,
    expiresAt: Date? = caducidad,
    gracePeriodExpiresAt: Date? = nil,
    isInBillingRetry: Bool = false,
    checkedAt: Date = caducidad - dia
) -> Entitlement {
    Entitlement(
        level: level,
        productID: "dev.threedots.paste.monthly",
        expiresAt: expiresAt,
        gracePeriodExpiresAt: gracePeriodExpiresAt,
        isInBillingRetry: isInBillingRetry,
        checkedAt: checkedAt
    )
}

// MARK: - Sin derecho

@Test func sinDerechoSeBloquea() {
    #expect(decideAccess(nil, now: caducidad, policy: .local) == .locked(.never))
    #expect(decideAccess(nil, now: caducidad, policy: .mirror) == .locked(.mirrorNeverSeen))
}

@Test func sinFechaDeCaducidadEsComoNoTenerNada() {
    let sinFecha = derecho(level: .none, expiresAt: nil)

    #expect(decideAccess(sinFecha, now: caducidad, policy: .local) == .locked(.never))
    #expect(decideAccess(sinFecha, now: caducidad, policy: .mirror) == .locked(.mirrorNeverSeen))
}

// MARK: - Periodo vivo

@Test func dentroDelPeriodoSeAbre() {
    let d = derecho()
    #expect(decideAccess(d, now: caducidad - dia, policy: .local) == .granted(.paid))
}

@Test func laPruebaSeDistingueDelPagado() {
    let prueba = derecho(level: .trial)

    #expect(
        decideAccess(prueba, now: caducidad - dia, policy: .local)
            == .granted(.trial(endsAt: caducidad))
    )
}

@Test func laCaducidadNoIncluyeSuPropioInstante() {
    // `now == expiresAt` ya está fuera: es el instante en el que Apple deja de
    // considerar la suscripción vigente.
    let d = derecho(checkedAt: caducidad + 3600)
    #expect(decideAccess(d, now: caducidad, policy: .local) == .locked(.expired))
}

// MARK: - Gracia y reintento de cobro

@Test func elPeriodoDeGraciaAbreLaApp() {
    let graciaHasta = caducidad + 10 * dia
    let d = derecho(gracePeriodExpiresAt: graciaHasta, checkedAt: caducidad + 3600)

    #expect(
        decideAccess(d, now: caducidad + 5 * dia, policy: .local)
            == .granted(.grace(endsAt: graciaHasta))
    )
    #expect(decideAccess(d, now: caducidad + 11 * dia, policy: .local) == .locked(.expired))
}

@Test func elReintentoDeCobroAbreLaAppDuranteLaVentanaDeApple() {
    let d = derecho(isInBillingRetry: true, checkedAt: caducidad + 3600)

    #expect(
        decideAccess(d, now: caducidad + 10 * dia, policy: .local)
            == .granted(.billingRetry(endsAt: caducidad + 16 * dia))
    )
    #expect(decideAccess(d, now: caducidad + 20 * dia, policy: .local) == .locked(.expired))
}

@Test func sinReintentoNoHayVentanaDeCobro() {
    let d = derecho(isInBillingRetry: false, checkedAt: caducidad + 3600)
    #expect(decideAccess(d, now: caducidad + dia, policy: .local) == .locked(.expired))
}

// MARK: - Sin conexión

@Test func loQueCaducoSinPoderVerificarseSeTolera() {
    let comprobado = caducidad - dia
    let d = derecho(checkedAt: comprobado)

    #expect(
        decideAccess(d, now: caducidad + 2 * dia, policy: .local)
            == .granted(.stale(since: comprobado))
    )
    #expect(decideAccess(d, now: caducidad + 4 * dia, policy: .local) == .locked(.expired))
}

@Test func loVerificadoComoCaducadoNoTieneMargen() {
    // Se preguntó después de la caducidad y la respuesta fue que no. Aquí no
    // vale la tolerancia: no es que no se supiera, es que se sabe.
    let d = derecho(checkedAt: caducidad + 3600)
    #expect(decideAccess(d, now: caducidad + 2 * 3600, policy: .local) == .locked(.expired))
}

@Test func elEspejoDelMacAguantaMasSinNoticias() {
    let comprobado = caducidad - dia
    let d = derecho(checkedAt: comprobado)

    // Lo que en el iPhone ya está bloqueado, en el Mac sigue abierto: el Mac
    // depende de que alguien abra el teléfono.
    #expect(decideAccess(d, now: caducidad + 10 * dia, policy: .local) == .locked(.expired))
    #expect(
        decideAccess(d, now: caducidad + 10 * dia, policy: .mirror)
            == .granted(.stale(since: comprobado))
    )
}

// MARK: - Motivos de bloqueo del espejo

@Test func elEspejoDistingueQuedarseSinNoticiasDeNoHaberPagado() {
    let sinNoticias = derecho(checkedAt: caducidad - dia)
    let verificado = derecho(checkedAt: caducidad + 3600)
    let muyDespues = caducidad + 40 * dia

    // Se arregla abriendo el iPhone.
    #expect(decideAccess(sinNoticias, now: muyDespues, policy: .mirror) == .locked(.mirrorStale))
    // Se arregla pagando.
    #expect(decideAccess(verificado, now: muyDespues, policy: .mirror) == .locked(.expired))
}

// MARK: - Compatibilidad hacia atrás

@Test func unNivelDesconocidoNoBloquea() throws {
    // Un iPhone con una versión más nueva escribe un nivel que este binario no
    // conoce. Mandan las fechas: la app se abre igual.
    let json = Data(#"""
    {"level":"family","expiresAt":757339200,"isInBillingRetry":false,"checkedAt":757252800}
    """#.utf8)

    let d = try EntitlementCoding.decoder.decode(Entitlement.self, from: json)

    #expect(d.level == .unknown)
    #expect(decideAccess(d, now: d.expiresAt! - dia, policy: .local) == .granted(.paid))
}
