import Foundation
import Testing
@testable import PasteCore

/// Suite propia por test: `UserDefaults` es global y dos tests que compartan
/// clave se pisan según el orden en que corran.
private func hacerDefaults() -> UserDefaults {
    let suite = "test.entitlement.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let momento = Date(timeIntervalSince1970: 1_000_000)

// MARK: - Caché

@Test func sinNadaGuardadoNoHayDerecho() {
    #expect(EntitlementStore(defaults: hacerDefaults()).load() == nil)
}

@Test func elDerechoSobreviveAlViajePorUserDefaults() {
    let store = EntitlementStore(defaults: hacerDefaults())
    let original = Entitlement(
        level: .trial,
        productID: "dev.threedots.paste.yearly",
        expiresAt: momento,
        gracePeriodExpiresAt: momento + 3600,
        isInBillingRetry: true,
        checkedAt: momento - 3600
    )

    store.save(original)

    #expect(store.load() == original)
}

@Test func guardarNadaBorraLoAnterior() {
    let store = EntitlementStore(defaults: hacerDefaults())
    store.save(Entitlement(level: .paid, expiresAt: momento, checkedAt: momento))

    store.save(nil)

    #expect(store.load() == nil)
}

@Test func unaCacheCorruptaSeLeeComoAusente() {
    // Es lo que decide entre "no hay derecho" y reventar al arrancar. Lo
    // primero lo arregla el usuario suscribiéndose; lo segundo, nadie.
    let defaults = hacerDefaults()
    defaults.set(Data("no soy json".utf8), forKey: "entitlement.current")

    #expect(EntitlementStore(defaults: defaults).load() == nil)
}

// MARK: - Espejo

@Test func elDerechoSobreviveAlViajePorElEspejo() throws {
    let original = Entitlement(
        level: .paid,
        productID: "dev.threedots.paste.monthly",
        expiresAt: momento,
        checkedAt: momento - 3600
    )

    let data = try EntitlementMirror.encode(original)

    #expect(EntitlementMirror.decode(data) == original)
}

@Test func unEspejoIlegibleNoDevuelveDerecho() {
    #expect(EntitlementMirror.decode(Data("vacío".utf8)) == nil)
}
