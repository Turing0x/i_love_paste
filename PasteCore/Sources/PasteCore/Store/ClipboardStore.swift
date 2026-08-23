import Foundation
import GRDB

/// Todas las operaciones sobre elementos y pinboards.
///
/// Nada fuera de este tipo escribe en la base de datos: así la deduplicación y
/// el marcado de lápidas tienen un único sitio donde poder equivocarse.
public struct ClipboardStore: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    // MARK: - Escritura

    /// Inserta el elemento, o si ya existe uno vivo con el mismo `contentHash`
    /// lo asciende al presente.
    ///
    /// Volver a copiar algo no debe crear una fila nueva: en un día normal se
    /// copia lo mismo decenas de veces y el historial se volvería inservible.
    /// Ascender significa `createdAt = ahora`, que es lo que lo devuelve a la
    /// cabeza de la lista.
    ///
    /// - Returns: el elemento tal como quedó almacenado.
    @discardableResult
    public func capture(_ item: ClipboardItem) throws -> ClipboardItem {
        try db.writer.write { db in
            let existing = try ClipboardItem
                .filter(ClipboardItem.Columns.contentHash == item.contentHash)
                .filter(ClipboardItem.Columns.deletedAt == nil)
                .fetchOne(db)

            guard var existing else {
                try item.insert(db)
                return item
            }

            let now = item.createdAt
            existing.createdAt = now
            existing.updatedAt = now
            // La app de origen se refresca: importa dónde se copió por última vez.
            existing.sourceBundleID = item.sourceBundleID
            existing.sourceAppName = item.sourceAppName
            existing.sourceDeviceID = item.sourceDeviceID
            try existing.update(db)
            return existing
        }
    }

    /// Marca el elemento como borrado sin quitar la fila.
    ///
    /// El borrado físico rompería la sincronización: el otro dispositivo, que
    /// no sabe nada del borrado, reenviaría el elemento en el siguiente ciclo.
    public func softDelete(id: UUID, at date: Date = Date()) throws {
        try db.writer.write { db in
            _ = try ClipboardItem
                .filter(key: id.uuidString)
                .updateAll(db, [
                    ClipboardItem.Columns.deletedAt.set(to: date),
                    ClipboardItem.Columns.updatedAt.set(to: date)
                ])
        }
    }

    /// Cambia el título manual. `nil` vuelve al título derivado del contenido.
    public func rename(id: UUID, to title: String?, at date: Date = Date()) throws {
        try db.writer.write { db in
            _ = try ClipboardItem
                .filter(key: id.uuidString)
                .updateAll(db, [
                    ClipboardItem.Columns.title.set(to: title),
                    ClipboardItem.Columns.updatedAt.set(to: date)
                ])
        }
    }

    /// Sustituye el texto de un elemento. Recalcula el hash, así que un elemento
    /// editado deja de deduplicarse contra el contenido del que salió.
    public func updateText(id: UUID, to text: String, at date: Date = Date()) throws {
        try db.writer.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id.uuidString) else { return }
            item.plainText = text
            item.contentHash = ContentHasher.hash(text: text)
            item.byteSize = text.utf8.count
            item.urlHost = item.kind == .url ? ClipboardItem.extractHost(from: text) : nil
            item.updatedAt = date
            try item.update(db)
        }
    }

    /// Mueve un elemento a un pinboard, o lo devuelve al historial con `nil`.
    /// Se coloca al final del destino.
    public func move(id: UUID, toPinboard pinboardID: UUID?, at date: Date = Date()) throws {
        try db.writer.write { db in
            let nextOrder = try Self.nextSortOrder(db, pinboardID: pinboardID)
            try ClipboardItem
                .filter(key: id.uuidString)
                .updateAll(db, [
                    ClipboardItem.Columns.pinboardID.set(to: pinboardID?.uuidString),
                    ClipboardItem.Columns.sortOrder.set(to: nextOrder),
                    ClipboardItem.Columns.updatedAt.set(to: date)
                ])
        }
    }

    /// Recoloca un elemento entre otros dos usando orden fraccional: solo se
    /// reescribe la fila movida, no toda la lista.
    ///
    /// - Parameters:
    ///   - after: elemento que quedará justo antes, o `nil` para el principio.
    ///   - before: elemento que quedará justo después, o `nil` para el final.
    public func reorder(
        id: UUID,
        after: Double?,
        before: Double?,
        at date: Date = Date()
    ) throws {
        let newOrder: Double
        switch (after, before) {
        case let (lo?, hi?): newOrder = (lo + hi) / 2
        case let (lo?, nil): newOrder = lo + 1
        case let (nil, hi?): newOrder = hi - 1
        case (nil, nil): newOrder = 0
        }
        try db.writer.write { db in
            _ = try ClipboardItem
                .filter(key: id.uuidString)
                .updateAll(db, [
                    ClipboardItem.Columns.sortOrder.set(to: newOrder),
                    ClipboardItem.Columns.updatedAt.set(to: date)
                ])
        }
    }

    // MARK: - Lectura

    /// Elementos que cumplen el filtro, más recientes primero (o en su orden
    /// manual si el ámbito es un pinboard).
    public func items(
        matching filter: HistoryFilter = .history,
        limit: Int = 200,
        offset: Int = 0
    ) throws -> [ClipboardItem] {
        try db.reader.read { db in
            var request = Self.baseRequest(filter)
            request = Self.applyOrdering(request, scope: filter.scope)
            return try request.limit(limit, offset: offset).fetchAll(db)
        }
    }

    /// Búsqueda por texto sobre el índice FTS5, restringida por el mismo filtro.
    ///
    /// Una consulta vacía o que no produzca ningún término utilizable equivale a
    /// no buscar, y devuelve el listado normal: si no fuera así, escribir un
    /// espacio vaciaría la pantalla.
    public func search(
        _ query: String,
        matching filter: HistoryFilter = .history,
        limit: Int = 200
    ) throws -> [ClipboardItem] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return try items(matching: filter, limit: limit)
        }
        return try db.reader.read { db in
            // El `MATCH` va contra la tabla FTS, no contra `clipboardItem`, así
            // que hay que unirlas por rowid en vez de filtrar directamente.
            let ftsAlias = TableAlias<ClipboardItemFTS>()
            let match = ClipboardItem.fts.aliased(ftsAlias).matching(pattern)

            // El orden lo da la relevancia de FTS5 (`rank`), no la fecha: al
            // buscar interesa el mejor resultado, no el más reciente.
            return try Self.baseRequest(filter)
                .joining(required: match)
                .order(ftsAlias[Column.rank])
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        try db.reader.read { db in
            try ClipboardItem.fetchOne(db, key: id.uuidString)
        }
    }

    /// Apps que han aportado algún elemento vivo, para poblar el filtro de origen.
    public func sourceApps() throws -> [(bundleID: String, name: String, count: Int)] {
        try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT sourceBundleID AS bundleID,
                       COALESCE(MAX(sourceAppName), sourceBundleID) AS name,
                       COUNT(*) AS count
                FROM clipboardItem
                WHERE deletedAt IS NULL AND sourceBundleID IS NOT NULL
                GROUP BY sourceBundleID
                ORDER BY count DESC
                """)
            return rows.map { ($0["bundleID"], $0["name"], $0["count"]) }
        }
    }

    // MARK: - Pinboards

    /// Inserta o actualiza un pinboard.
    public func save(_ pinboard: Pinboard) throws {
        try db.writer.write { db in
            try pinboard.save(db)
        }
    }

    /// Pinboards vivos, en su orden manual.
    public func pinboards() throws -> [Pinboard] {
        try db.reader.read { db in
            try Pinboard
                .filter(Pinboard.Columns.deletedAt == nil)
                .order(Pinboard.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    /// Marca el pinboard como borrado y devuelve sus elementos al historial.
    ///
    /// Los elementos no se borran con él: perder contenido guardado a propósito
    /// por eliminar la carpeta que lo contenía sería lo peor que puede hacer
    /// esta app.
    public func deletePinboard(id: UUID, at date: Date = Date()) throws {
        try db.writer.write { db in
            try Pinboard
                .filter(key: id.uuidString)
                .updateAll(db, [
                    Pinboard.Columns.deletedAt.set(to: date),
                    Pinboard.Columns.updatedAt.set(to: date)
                ])
            try ClipboardItem
                .filter(ClipboardItem.Columns.pinboardID == id.uuidString)
                .updateAll(db, [
                    ClipboardItem.Columns.pinboardID.set(to: nil as String?),
                    ClipboardItem.Columns.updatedAt.set(to: date)
                ])
        }
    }

    // MARK: - Retención

    /// Marca como borrados los elementos de historial más viejos que `maxAge` o
    /// que sobren respecto de `maxItems`.
    ///
    /// Nunca toca los elementos que están en un pinboard: la razón de existir de
    /// un pinboard es precisamente que su contenido no caduca.
    ///
    /// - Returns: cuántos elementos se marcaron.
    @discardableResult
    public func applyRetention(
        maxAge: TimeInterval?,
        maxItems: Int?,
        now: Date = Date()
    ) throws -> Int {
        try db.writer.write { db in
            var purged = 0

            if let maxAge {
                let cutoff = now.addingTimeInterval(-maxAge)
                purged += try ClipboardItem
                    .filter(ClipboardItem.Columns.deletedAt == nil)
                    .filter(ClipboardItem.Columns.pinboardID == nil)
                    .filter(ClipboardItem.Columns.createdAt < cutoff)
                    .updateAll(db, [
                        ClipboardItem.Columns.deletedAt.set(to: now),
                        ClipboardItem.Columns.updatedAt.set(to: now)
                    ])
            }

            if let maxItems {
                let survivors = try ClipboardItem
                    .select(ClipboardItem.Columns.id, as: String.self)
                    .filter(ClipboardItem.Columns.deletedAt == nil)
                    .filter(ClipboardItem.Columns.pinboardID == nil)
                    .order(ClipboardItem.Columns.createdAt.desc)
                    .limit(maxItems)
                    .fetchAll(db)

                purged += try ClipboardItem
                    .filter(ClipboardItem.Columns.deletedAt == nil)
                    .filter(ClipboardItem.Columns.pinboardID == nil)
                    .filter(!survivors.contains(ClipboardItem.Columns.id))
                    .updateAll(db, [
                        ClipboardItem.Columns.deletedAt.set(to: now),
                        ClipboardItem.Columns.updatedAt.set(to: now)
                    ])
            }

            return purged
        }
    }

    /// Borra de verdad las lápidas anteriores a `olderThan`, y devuelve las
    /// rutas de blob que quedaron sin dueño para que el llamante borre los
    /// ficheros.
    ///
    /// Se espera antes de purgar para que un borrado hecho en un dispositivo
    /// tenga tiempo de propagarse al otro cuando exista sincronización.
    public func purgeTombstones(olderThan cutoff: Date) throws -> [String] {
        try db.writer.write { db in
            let doomed = try ClipboardItem
                .filter(ClipboardItem.Columns.deletedAt != nil)
                .filter(ClipboardItem.Columns.deletedAt < cutoff)
                .fetchAll(db)

            let ids = doomed.map(\.id.uuidString)
            try ClipboardItem.filter(keys: ids).deleteAll(db)

            // Varios elementos pueden compartir blob (mismo contenido, distinto
            // momento), así que solo son borrables los que ya no referencia nadie.
            let orphans = try doomed.compactMap(\.blobPath).filter { path in
                try ClipboardItem
                    .filter(Column("blobPath") == path)
                    .fetchCount(db) == 0
            }
            return Array(Set(orphans))
        }
    }

    // MARK: - Auxiliares

    private static func baseRequest(_ filter: HistoryFilter) -> QueryInterfaceRequest<ClipboardItem> {
        var request = ClipboardItem.filter(ClipboardItem.Columns.deletedAt == nil)

        switch filter.scope {
        case .history:
            request = request.filter(ClipboardItem.Columns.pinboardID == nil)
        case .pinboard(let id):
            request = request.filter(ClipboardItem.Columns.pinboardID == id.uuidString)
        case .everything:
            break
        }

        if !filter.kinds.isEmpty {
            request = request.filter(filter.kinds.map(\.rawValue).contains(ClipboardItem.Columns.kind))
        }
        if !filter.bundleIDs.isEmpty {
            request = request.filter(Array(filter.bundleIDs).contains(ClipboardItem.Columns.sourceBundleID))
        }
        if !filter.deviceIDs.isEmpty {
            let ids = filter.deviceIDs.map(\.uuidString)
            request = request.filter(ids.contains(ClipboardItem.Columns.sourceDeviceID))
        }
        if let after = filter.createdAfter {
            request = request.filter(ClipboardItem.Columns.createdAt >= after)
        }
        if let before = filter.createdBefore {
            request = request.filter(ClipboardItem.Columns.createdAt < before)
        }
        return request
    }

    private static func applyOrdering(
        _ request: QueryInterfaceRequest<ClipboardItem>,
        scope: HistoryFilter.Scope
    ) -> QueryInterfaceRequest<ClipboardItem> {
        switch scope {
        case .pinboard:
            // Dentro de un pinboard manda el orden que puso el usuario.
            return request.order(ClipboardItem.Columns.sortOrder)
        case .history, .everything:
            return request.order(ClipboardItem.Columns.createdAt.desc)
        }
    }

    private static func nextSortOrder(_ db: Database, pinboardID: UUID?) throws -> Double {
        let request = ClipboardItem
            .filter(ClipboardItem.Columns.deletedAt == nil)
            .filter(pinboardID.map {
                ClipboardItem.Columns.pinboardID == $0.uuidString
            } ?? (ClipboardItem.Columns.pinboardID == nil))
        let maxOrder = try Double.fetchOne(
            db,
            request.select(max(ClipboardItem.Columns.sortOrder))
        )
        return (maxOrder ?? 0) + 1
    }
}
