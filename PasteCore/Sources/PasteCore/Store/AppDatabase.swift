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
        // Sin `eraseDatabaseOnSchemaChange`: a partir de M1 la base contiene el
        // historial real del usuario, y reconstruirla en silencio al tocar una
        // migración lo borraría entero. Los cambios de esquema van en
        // migraciones nuevas.
        var migrator = DatabaseMigrator()

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

        // `foreignKeyChecks: .deferred` porque esta migración reconstruye
        // `clipboardItem`: durante el trasvase la tabla vieja y la nueva conviven
        // y las referencias no cuadran hasta el final.
        migrator.registerMigration("v2.sync", foreignKeyChecks: .deferred) { db in
            // `clipboardItem` se rehace sin la clave ajena contra `pinboard`.
            //
            // Es el mismo motivo por el que `sourceDeviceID` nunca la tuvo: al
            // sincronizar, un elemento puede llegar antes que el pinboard al que
            // pertenece, porque el servidor entrega los cambios por lotes y no
            // promete que vengan juntos. Con la clave ajena esa inserción falla.
            //
            // No se pierde comportamiento: `deletePinboard` ya pone los
            // `pinboardID` a nulo a mano en vez de fiarse de `onDelete`.

            // El índice FTS se tira antes y se rehace después: sus triggers
            // cuelgan de `clipboardItem` y se irían con la tabla vieja.
            try db.drop(table: "clipboardItem_fts")

            try db.create(table: "clipboardItem_v2") { t in
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
                t.column("sourceDeviceID", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("pinboardID", .text)
                t.column("sortOrder", .double).notNull().defaults(to: 0)
            }
            try db.execute(sql: """
                INSERT INTO clipboardItem_v2
                SELECT id, contentHash, kind, plainText, richData, blobPath,
                       byteSize, title, sourceBundleID, sourceAppName, urlHost,
                       sourceDeviceID, createdAt, updatedAt, deletedAt,
                       pinboardID, sortOrder
                FROM clipboardItem
                """)
            try db.drop(table: "clipboardItem")
            try db.rename(table: "clipboardItem_v2", to: "clipboardItem")

            // Los índices se van con la tabla vieja, así que se rehacen igual
            // que en `v1.schema`.
            try db.create(
                index: "clipboardItem_hash_unique",
                on: "clipboardItem",
                columns: ["contentHash"],
                unique: true,
                condition: Column("deletedAt") == nil
            )
            try db.execute(
                sql: """
                    CREATE INDEX clipboardItem_history
                    ON clipboardItem(createdAt DESC)
                    WHERE deletedAt IS NULL AND pinboardID IS NULL
                    """
            )
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

            // `synchronize` repuebla el índice a partir de la tabla y vuelve a
            // instalar sus triggers.
            try db.create(virtualTable: "clipboardItem_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboardItem")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("title")
                t.column("plainText")
                t.column("sourceAppName")
                t.column("urlHost")
            }

            // Campos de sistema del `CKRecord` de cada fila. Sin ellos no hay
            // etiqueta de cambio que enviar, y cada subida llegaría al servidor
            // como un conflicto contra su propia versión anterior.
            try db.create(table: "ckRecordMetadata") { t in
                t.primaryKey("recordName", .text)
                t.column("tableName", .text).notNull()
                t.column("systemFields", .blob).notNull()
            }

            // Qué falta por subir. La clave primaria es el registro, así que
            // tocar diez veces la misma fila deja una entrada, no diez.
            try db.create(table: "pendingSyncChange") { t in
                t.primaryKey("recordName", .text)
                t.column("tableName", .text).notNull()
                t.column("queuedAt", .datetime).notNull()
            }

            // Estado de `CKSyncEngine`. Una sola fila, y el `CHECK` lo garantiza
            // en vez de confiar en que nadie inserte una segunda.
            try db.create(table: "syncEngineState") { t in
                t.column("id", .integer).primaryKey().check { $0 == 1 }
                t.column("state", .blob)
            }

            // La cola se llena con triggers y no desde Swift por el mismo motivo
            // que el índice FTS5 usa `synchronize(withTable:)`: así ningún
            // camino de escritura puede olvidarse de encolar. `capture`,
            // `move`, `reorder`, `applyRetention` y lo que venga después quedan
            // cubiertos sin tocarlos.
            //
            // No hay trigger de DELETE: el único borrado físico es
            // `purgeTombstones`, y para entonces la lápida ya viajó. Cada
            // dispositivo purga la suya con la misma ventana.
            for table in ["clipboardItem", "pinboard", "device"] {
                for event in ["INSERT", "UPDATE"] {
                    try db.execute(sql: """
                        CREATE TRIGGER \(table)_sync_\(event.lowercased())
                        AFTER \(event) ON \(table)
                        BEGIN
                            INSERT INTO pendingSyncChange (recordName, tableName, queuedAt)
                            VALUES (NEW.id, '\(table)', strftime('%Y-%m-%d %H:%M:%f', 'now'))
                            ON CONFLICT(recordName) DO UPDATE SET queuedAt = excluded.queuedAt;
                        END
                        """)
                }
            }
        }

        return migrator
    }
}
