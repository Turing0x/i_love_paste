import Foundation

/// Forma del derecho cuando viaja del iPhone al Mac por CloudKit.
///
/// No importa CloudKit: aquí solo vive el contrato —nombres y bytes— para que
/// los dos extremos se puedan probar sin nube. El pegamento con `CKRecord` vive
/// en cada app.
///
/// El registro va en la **zona por omisión** de la base privada, nunca en
/// `PasteZone`. El seguimiento de cambios de base de datos no cubre la zona por
/// omisión, así que `CKSyncEngine` no puede verlo ni clasificarlo mal; una zona
/// personalizada sí se le reporta.
public enum EntitlementMirror {
    public static let recordType = "Entitlement"

    /// Nombre fijo: siempre hay un registro y siempre se lee por identificador,
    /// nunca por consulta. Así no hace falta índice en el esquema de CloudKit.
    public static let recordName = "entitlement-v1"

    /// El derecho entero viaja como un JSON en un solo campo en vez de repartido
    /// en campos sueltos: añadir un dato más no toca el esquema de CloudKit, que
    /// hay que desplegar a producción a mano y no se puede deshacer.
    public static let payloadField = "payload"

    public static func encode(_ entitlement: Entitlement) throws -> Data {
        try EntitlementCoding.encoder.encode(entitlement)
    }

    public static func decode(_ data: Data) -> Entitlement? {
        try? EntitlementCoding.decoder.decode(Entitlement.self, from: data)
    }
}
