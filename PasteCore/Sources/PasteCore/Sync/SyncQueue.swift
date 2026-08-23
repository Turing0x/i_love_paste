import Foundation
import GRDB

/// Tablas que se sincronizan. El valor bruto es el nombre real de la tabla, que
/// es lo que escriben los triggers.
public enum SyncTable: String, Codable, Sendable {
    case clipboardItem
    case pinboard
    case device
}

/// Una fila local que todavía no ha subido.
///
/// La llenan los triggers de la migración `v2.sync`, no el código Swift: así
/// ningún camino de escritura puede olvidarse de encolar, igual que ninguno
/// puede olvidarse de actualizar el índice FTS5.
public struct PendingSyncChange: Codable, Equatable, Sendable {
    public var recordName: String
    public var tableName: SyncTable
    public var queuedAt: Date
}

extension PendingSyncChange: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pendingSyncChange"

    public enum Columns {
        public static let recordName = Column("recordName")
        public static let tableName = Column("tableName")
        public static let queuedAt = Column("queuedAt")
    }
}

/// Campos de sistema del `CKRecord` correspondiente a una fila.
///
/// Se guardan porque llevan la etiqueta de cambio: subir sin ella convierte cada
/// escritura en un conflicto contra la versión anterior de uno mismo.
struct CKRecordMetadata: Codable, Equatable, Sendable {
    var recordName: String
    var tableName: SyncTable
    var systemFields: Data
}

extension CKRecordMetadata: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ckRecordMetadata"
}

/// La única fila de `syncEngineState`.
struct SyncEngineState: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncEngineState"

    var id: Int = 1
    var state: Data?
}

/// Un lote de cambios bajado del servidor.
///
/// No sabe nada de CloudKit: el motor traduce los `CKRecord` a esto, y así la
/// reconciliación entera se prueba sin red.
public struct RemoteBatch: Equatable, Sendable {
    public var items: [ClipboardItem]
    public var pinboards: [Pinboard]
    public var devices: [Device]

    /// Registros que el servidor ya no tiene. Aquí el borrado sí es físico.
    public var deletedRecordNames: [String]

    public init(
        items: [ClipboardItem] = [],
        pinboards: [Pinboard] = [],
        devices: [Device] = [],
        deletedRecordNames: [String] = []
    ) {
        self.items = items
        self.pinboards = pinboards
        self.devices = devices
        self.deletedRecordNames = deletedRecordNames
    }
}
