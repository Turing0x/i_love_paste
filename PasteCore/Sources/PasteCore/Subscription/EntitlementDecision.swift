import Foundation

/// Cuánto se estira un derecho que ya no se puede verificar.
///
/// Existe porque el muro es duro: sin estas ventanas, a quien paga se le cierra
/// la app porque le haya caducado la tarjeta o porque lleve el fin de semana sin
/// cobertura, y eso genera más bajas que cualquier fallo de cobro.
public struct EntitlementPolicy: Equatable, Sendable {
    /// Ventana de reintento de cobro. Son los 16 días que Apple tarda como mucho
    /// en resolver un cobro fallido antes de dar la suscripción por perdida.
    public var billingRetry: TimeInterval

    /// Cuánto se sigue abriendo la app tras la fecha de caducidad cuando no se ha
    /// podido volver a preguntar desde entonces.
    public var offline: TimeInterval

    /// El Mac no ve StoreKit: lee una copia que escribió el iPhone. Cambia los
    /// motivos de bloqueo (no es lo mismo "no has pagado" que "este Mac no ha
    /// visto nunca el espejo") y alarga la ventana sin conexión.
    public var isMirror: Bool

    public init(billingRetry: TimeInterval, offline: TimeInterval, isMirror: Bool) {
        self.billingRetry = billingRetry
        self.offline = offline
        self.isMirror = isMirror
    }

    private static let day: TimeInterval = 24 * 3600

    /// iPhone: StoreKit está a mano, así que si no se ha podido verificar en tres
    /// días es que algo va mal de verdad.
    public static let local = EntitlementPolicy(
        billingRetry: 16 * day,
        offline: 3 * day,
        isMirror: false
    )

    /// Mac: depende de que el iPhone se abra y publique. Un mes de margen es lo
    /// que evita que unas vacaciones sin tocar el teléfono bloqueen el Mac.
    public static let mirror = EntitlementPolicy(
        billingRetry: 16 * day,
        offline: 30 * day,
        isMirror: true
    )
}

/// Por qué está abierta la app. El motivo importa porque cada uno se enseña
/// distinto: una prueba a punto de acabar y un cobro fallido piden cosas
/// diferentes al usuario.
public enum Access: Equatable, Sendable {
    case paid
    case trial(endsAt: Date)
    case grace(endsAt: Date)
    case billingRetry(endsAt: Date)
    case stale(since: Date)
}

public enum LockReason: Equatable, Sendable {
    /// Nunca ha habido suscripción en este dispositivo.
    case never
    /// La hubo, se verificó que terminó y ya no queda margen.
    case expired
    /// El Mac no ha conseguido leer el espejo ni una vez: o no hay iCloud, o es
    /// otra cuenta distinta a la del iPhone.
    case mirrorNeverSeen
    /// El Mac leyó el espejo hace tanto que ya no se sostiene.
    case mirrorStale
}

public enum AccessDecision: Equatable, Sendable {
    case granted(Access)
    case locked(LockReason)

    public var isGranted: Bool {
        if case .granted = self { true } else { false }
    }
}

/// Decide si se abre la app.
///
/// Pura y sin StoreKit a propósito: es la única pieza de todo el muro que se
/// puede probar entera, y toda la lógica que se le escape acaba solo verificable
/// a mano contra la App Store.
public func decideAccess(
    _ entitlement: Entitlement?,
    now: Date = Date(),
    policy: EntitlementPolicy
) -> AccessDecision {
    guard let entitlement else {
        return .locked(policy.isMirror ? .mirrorNeverSeen : .never)
    }

    // Sin fecha de caducidad no hay ventana que mirar: es el estado de quien
    // nunca se ha suscrito, no el de una suscripción sin fin.
    guard let expiresAt = entitlement.expiresAt else {
        return .locked(policy.isMirror ? .mirrorNeverSeen : .never)
    }

    if now < expiresAt {
        return .granted(entitlement.level == .trial ? .trial(endsAt: expiresAt) : .paid)
    }

    if let graceEnd = entitlement.gracePeriodExpiresAt, now < graceEnd {
        return .granted(.grace(endsAt: graceEnd))
    }

    if entitlement.isInBillingRetry {
        let retryEnd = expiresAt + policy.billingRetry
        if now < retryEnd { return .granted(.billingRetry(endsAt: retryEnd)) }
    }

    // La comprobación es anterior a la caducidad: caducó sin que nadie pudiera
    // volver a preguntar. Si fuese posterior, es que se preguntó y la respuesta
    // fue que no, y ahí no hay margen que valga.
    let sinVerificarDesdeLaCaducidad = entitlement.checkedAt < expiresAt
    if sinVerificarDesdeLaCaducidad, now < expiresAt + policy.offline {
        return .granted(.stale(since: entitlement.checkedAt))
    }

    // Se agotó el margen sin noticias frente a "se verificó que terminó": en el
    // Mac son dos mensajes distintos, porque el primero se arregla abriendo el
    // iPhone y el segundo pagando.
    if policy.isMirror, sinVerificarDesdeLaCaducidad {
        return .locked(.mirrorStale)
    }

    return .locked(.expired)
}
