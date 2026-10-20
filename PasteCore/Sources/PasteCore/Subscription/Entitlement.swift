import Foundation

/// Nivel de suscripción, tal y como lo vio quien escribió el derecho.
///
/// Es informativo: quien decide si se abre la app son las fechas de
/// `Entitlement`, no esto. Por eso un valor desconocido no revienta la
/// descodificación — un iPhone con una versión más nueva puede escribir un nivel
/// que este binario no conoce, y tirar el derecho entero por eso dejaría fuera a
/// alguien que sí paga.
public enum EntitlementLevel: String, Codable, Sendable {
    case none
    case trial
    case paid
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EntitlementLevel(rawValue: raw) ?? .unknown
    }
}

/// Lo que se sabe de la suscripción del usuario en un momento dado.
///
/// Lo produce StoreKit en el iPhone, se cachea en el grupo compartido y viaja al
/// Mac por CloudKit. Las tres copias tienen esta misma forma.
public struct Entitlement: Codable, Equatable, Sendable {
    public var level: EntitlementLevel

    public var productID: String?

    /// Fin del periodo pagado o de la prueba. `nil` significa que nunca ha
    /// habido suscripción, no que sea eterna.
    public var expiresAt: Date?

    /// Fin del periodo de gracia que concede Apple cuando falla el cobro pero la
    /// suscripción sigue viva.
    public var gracePeriodExpiresAt: Date?

    public var isInBillingRetry: Bool

    /// Cuándo se comprobó esto contra StoreKit. Es lo que distingue "caducó y lo
    /// hemos verificado" de "caducó mientras el dispositivo estaba sin red", que
    /// se tratan de forma muy distinta.
    public var checkedAt: Date

    public init(
        level: EntitlementLevel = .none,
        productID: String? = nil,
        expiresAt: Date? = nil,
        gracePeriodExpiresAt: Date? = nil,
        isInBillingRetry: Bool = false,
        checkedAt: Date = Date()
    ) {
        self.level = level
        self.productID = productID
        self.expiresAt = expiresAt
        self.gracePeriodExpiresAt = gracePeriodExpiresAt
        self.isInBillingRetry = isInBillingRetry
        self.checkedAt = checkedAt
    }
}

/// Codificación compartida por la caché de `UserDefaults` y el espejo de
/// CloudKit: las dos guardan el mismo JSON, así que una sola pareja de
/// codificadores evita que se separen.
/// Se construyen en cada uso en vez de guardarse: un `JSONEncoder` estático es
/// estado global mutable, y la concurrencia estricta lo rechaza. El derecho se
/// codifica un puñado de veces por sesión, así que no compensa envolverlo.
enum EntitlementCoding {
    static var encoder: JSONEncoder { JSONEncoder() }
    static var decoder: JSONDecoder { JSONDecoder() }
}
