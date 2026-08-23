import Foundation
import GRDB

/// Punto de entrada a la base de datos. Es propietaria del `DatabaseWriter` y
/// del migrador de esquema; el resto del paquete recibe la instancia ya migrada.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public var reader: any DatabaseReader { writer }

    /// - Parameter writer: cola o pool ya abierto. La migración se aplica aquí,
    ///   de modo que un `AppDatabase` construido siempre está al día.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Base de datos en memoria, para tests y previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue())
    }

    /// Abre la base de datos en disco, creando el directorio si hace falta.
    ///
    /// Se usa `DatabasePool` (WAL) para que las lecturas de la interfaz no
    /// bloqueen las escrituras del capturador, que ocurren cada pocos segundos.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(try DatabasePool(path: url.path, configuration: config))
    }
}

// MARK: - Esquema

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Durante el desarrollo, cambiar una migración ya aplicada borra la base
        // y la reconstruye en vez de fallar. Quitar antes de usar en serio.
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1.schema") { db in
            try db.create(table: "device") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("platform", .text).notNull()
                t.column("lastSeenAt", .datetime).notNull()
            }

            try db.create(table: "pinboard") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("sortOrder", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "pinboard_order", on: "pinboard", columns: ["sortOrder"])

            try db.create(table: "clipboardItem") { t in
                t.primaryKey("id", .text)
                t.column("contentHash", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("plainText", .text)
                t.column("richData", .blob)
                t.column("blobPath", .text)
                t.column("byteSize", .integer).notNull().defaults(to: 0)
                t.column("title", .text)
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("urlHost", .text)
                // Sin clave ajena contra `device` a propósito: es metadato
                // descriptivo, y al sincronizar un elemento puede llegar antes
                // que el registro del dispositivo que lo creó.
                t.column("sourceDeviceID", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("pinboardID", .text)
                    .references("pinboard", onDelete: .setNull)
                t.column("sortOrder", .double).notNull().defaults(to: 0)
            }

            // Deduplicación a nivel de base de datos. Es un índice parcial: las
            // lápidas quedan fuera, así que volver a copiar algo que se borró
            // crea una fila nueva en vez de chocar con la vieja.
            try db.create(
                index: "clipboardItem_hash_unique",
                on: "clipboardItem",
                columns: ["contentHash"],
                unique: true,
                condition: Column("deletedAt") == nil
            )

            // Consulta principal del historial: vivos, sin pinboard, recientes primero.
            try db.execute(
                sql: """
                    CREATE INDEX clipboardItem_history
                    ON clipboardItem(createdAt DESC)
                    WHERE deletedAt IS NULL AND pinboardID IS NULL
                    """
            )
            // Consulta de un pinboard concreto, en su orden manual.
            try db.execute(
                sql: """
                    CREATE INDEX clipboardItem_board
                    ON clipboardItem(pinboardID, sortOrder)
                    WHERE deletedAt IS NULL
                    """
            )
            try db.create(
                index: "clipboardItem_bundle",
                on: "clipboardItem",
                columns: ["sourceBundleID"]
            )
            try db.create(
                index: "clipboardItem_device",
                on: "clipboardItem",
                columns: ["sourceDeviceID"]
            )

            // Índice de búsqueda. `synchronize` instala los triggers que lo
            // mantienen al día con la tabla real, de modo que ningún camino de
            // escritura puede olvidarse de actualizarlo.
            //
            // `unicode61 remove_diacritics 2` hace que "codigo" encuentre
            // "código", imprescindible escribiendo en español.
            try db.create(virtualTable: "clipboardItem_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboardItem")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("title")
                t.column("plainText")
                t.column("sourceAppName")
                t.column("urlHost")
            }
        }

        return migrator
    }
}
