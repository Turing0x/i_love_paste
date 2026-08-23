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
        let newOrder = Self.fractionalOrder(after: after, before: before)
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
        try db.reader.read { db in
            try Self.request(query: query, filter: filter, limit: limit).fetchAll(db)
        }
    }

    /// Secuencia que emite el listado cada vez que cambia algo que le afecta.
    ///
    /// Es lo que hace que la lista se actualice sola al copiar, sin que el
    /// capturador tenga que avisar a la interfaz: GRDB deduce las tablas
    /// implicadas de la propia consulta y la vuelve a ejecutar.
    ///
    /// Vale también para búsqueda en vivo. GRDB, ante cambios en tablas
    /// virtuales, da la región por modificada, así que los resultados sobre el
    /// índice FTS también se refrescan.
    public func observeItems(
        query: String = "",
        matching filter: HistoryFilter = .history,
        limit: Int = 200
    ) -> AsyncValueObservation<[ClipboardItem]> {
        ValueObservation
            .tracking { db in
                try Self.request(query: query, filter: filter, limit: limit).fetchAll(db)
            }
            .values(in: db.reader)
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

    // MARK: - Dispositivos

    /// Inserta o actualiza el registro de un dispositivo.
    ///
    /// Se llama en cada arranque: el nombre del Mac cambia, y `lastSeenAt` es lo
    /// que permitirá saber qué dispositivos siguen vivos cuando haya
    /// sincronización.
    public func registerDevice(_ device: Device) throws {
        try db.writer.write { db in
            try device.save(db)
        }
    }

    public func devices() throws -> [Device] {
        try db.reader.read { db in
            try Device.fetchAll(db)
        }
    }

    // MARK: - Pinboards

    /// Inserta o actualiza un pinboard.
    public func save(_ pinboard: Pinboard) throws {
        try db.writer.write { db in
            try pinboard.save(db)
        }
    }

    /// Crea un pinboard al final de la lista.
    ///
    /// Existe además de `save` para que quien lo llame no tenga que inventarse
    /// el `sortOrder`: calcularlo mal deja dos pinboards empatados y el orden
    /// de la barra lateral pasa a depender de la suerte.
    @discardableResult
    public func createPinboard(
        name: String,
        colorHex: String = Pinboard.defaultColorHex,
        at date: Date = Date()
    ) throws -> Pinboard {
        try db.writer.write { db in
            let pinboard = Pinboard(
                name: name,
                colorHex: colorHex,
                sortOrder: try Self.nextPinboardSortOrder(db),
                createdAt: date,
                updatedAt: date
            )
            try pinboard.insert(db)
            return pinboard
        }
    }

    /// Pinboards vivos, en su orden manual.
    public func pinboards() throws -> [Pinboard] {
        try db.reader.read { db in
            try Self.livePinboards().fetchAll(db)
        }
    }

    /// Secuencia que emite los pinboards cada vez que cambian.
    ///
    /// La barra lateral tiene que repintarse sola al crear, renombrar o borrar,
    /// igual que la lista se repinta al copiar.
    public func observePinboards() -> AsyncValueObservation<[Pinboard]> {
        ValueObservation
            .tracking { db in
                try Self.livePinboards().fetchAll(db)
            }
            .values(in: db.reader)
    }

    /// Cambia el nombre, el color, o ambos. Lo que llegue `nil` se deja como está.
    public func updatePinboard(
        id: UUID,
        name: String? = nil,
        colorHex: String? = nil,
        at date: Date = Date()
    ) throws {
        var assignments: [ColumnAssignment] = [Pinboard.Columns.updatedAt.set(to: date)]
        if let name { assignments.append(Pinboard.Columns.name.set(to: name)) }
        if let colorHex { assignments.append(Pinboard.Columns.colorHex.set(to: colorHex)) }

        try db.writer.write { db in
            _ = try Pinboard.filter(key: id.uuidString).updateAll(db, assignments)
        }
    }

    /// Recoloca un pinboard entre otros dos. Mismo orden fraccional que los
    /// elementos: reordenar reescribe una fila, no la lista entera.
    public func reorderPinboard(
        id: UUID,
        after: Double?,
        before: Double?,
        at date: Date = Date()
    ) throws {
        let newOrder = Self.fractionalOrder(after: after, before: before)
        try db.writer.write { db in
            _ = try Pinboard
                .filter(key: id.uuidString)
                .updateAll(db, [
                    Pinboard.Columns.sortOrder.set(to: newOrder),
                    Pinboard.Columns.updatedAt.set(to: date)
                ])
        }
    }

    /// Cuántos elementos vivos tiene cada pinboard, para el contador de la barra
    /// lateral. Los pinboards vacíos no salen en el diccionario.
    public func pinboardCounts() throws -> [UUID: Int] {
        try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pinboardID, COUNT(*) AS count
                FROM clipboardItem
                WHERE deletedAt IS NULL AND pinboardID IS NOT NULL
                GROUP BY pinboardID
                """)
            return rows.reduce(into: [:]) { counts, row in
                guard let id = UUID(uuidString: row["pinboardID"]) else { return }
                counts[id] = row["count"]
            }
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

    // MARK: - Sincronización

    /// Filas pendientes de subir, las más antiguas primero.
    public func pendingChanges(limit: Int = 200) throws -> [PendingSyncChange] {
        try db.reader.read { db in
            try PendingSyncChange
                .order(PendingSyncChange.Columns.queuedAt)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Secuencia que emite la cola cada vez que cambia.
    ///
    /// Es lo que conecta los triggers con el motor: cualquier escritura local
    /// encola, y esto despierta a quien tenga que subirla, sin que ningún camino
    /// de escritura tenga que acordarse de avisar.
    public func observePendingChanges(limit: Int = 200) -> AsyncValueObservation<[PendingSyncChange]> {
        ValueObservation
            .tracking { db in
                try PendingSyncChange
                    .order(PendingSyncChange.Columns.queuedAt)
                    .limit(limit)
                    .fetchAll(db)
            }
            .values(in: db.reader)
    }

    /// Desencola lo que ya subió.
    public func clearPending(recordNames: [String]) throws {
        guard !recordNames.isEmpty else { return }
        try db.writer.write { db in
            _ = try PendingSyncChange.filter(keys: recordNames).deleteAll(db)
        }
    }

    /// Ejecuta una escritura procedente del servidor y desencola sus registros
    /// **en la misma transacción**.
    ///
    /// Es lo que corta el bucle de eco: aplicar un cambio remoto dispara los
    /// triggers, que lo encolarían para volver a subirlo, y de ahí a subir y
    /// bajar lo mismo indefinidamente. Al ir todo en una única escritura no hay
    /// ventana en la que la cola quede sucia.
    @discardableResult
    public func applyingRemote<T>(
        recordNames: [String],
        _ work: (Database) throws -> T
    ) throws -> T {
        try db.writer.write { db in
            let result = try work(db)
            if !recordNames.isEmpty {
                _ = try PendingSyncChange.filter(keys: recordNames).deleteAll(db)
            }
            return result
        }
    }

    /// Aplica un lote bajado del servidor en una única transacción.
    ///
    /// Los pinboards se aplican antes que los elementos porque un elemento puede
    /// referenciar uno recién creado.
    ///
    /// - Returns: los `recordName` que hay que volver a subir, porque ganó la
    ///   versión local o porque resolver un duplicado cambió ambas filas.
    @discardableResult
    public func applyRemote(_ batch: RemoteBatch, now: Date = Date()) throws -> [String] {
        try db.writer.write { db in
            var needsUpload: [String] = []
            var applied: [String] = []

            for remote in batch.pinboards {
                let local = try Pinboard.fetchOne(db, key: remote.id.uuidString)
                switch SyncReconciler.resolve(local: local, remote: remote) {
                case .remote:
                    try remote.save(db)
                    applied.append(remote.id.uuidString)
                case .local:
                    needsUpload.append(remote.id.uuidString)
                }
            }

            for remote in batch.devices {
                let local = try Device.fetchOne(db, key: remote.id.uuidString)
                switch SyncReconciler.resolve(local: local, remote: remote) {
                case .remote:
                    try remote.save(db)
                    applied.append(remote.id.uuidString)
                case .local:
                    needsUpload.append(remote.id.uuidString)
                }
            }

            for remote in batch.items {
                let local = try ClipboardItem.fetchOne(db, key: remote.id.uuidString)
                guard SyncReconciler.resolve(local: local, remote: remote) == .remote else {
                    needsUpload.append(remote.id.uuidString)
                    continue
                }

                if remote.deletedAt == nil, let duplicate = try Self.liveDuplicate(db, of: remote) {
                    let (winner, loser) = SyncReconciler.resolveDuplicate(remote, duplicate, at: now)
                    // La lápida primero: el índice único es parcial sobre los
                    // vivos, así que guardar antes al ganador chocaría contra el
                    // duplicado que todavía está vivo.
                    try loser.save(db)
                    try winner.save(db)
                    // Los dos cambian y los dos suben. La lápida es justo lo que
                    // hace que el dispositivo que creó el duplicado se entere.
                    needsUpload.append(winner.id.uuidString)
                    needsUpload.append(loser.id.uuidString)
                    continue
                }

                try remote.save(db)
                applied.append(remote.id.uuidString)
            }

            // Registros que el servidor ya no tiene: aquí el borrado sí es
            // físico, porque la lápida ya cumplió su función.
            for name in batch.deletedRecordNames {
                _ = try ClipboardItem.filter(key: name).deleteAll(db)
                _ = try Pinboard.filter(key: name).deleteAll(db)
                _ = try Device.filter(key: name).deleteAll(db)
                _ = try CKRecordMetadata.filter(key: name).deleteAll(db)
                applied.append(name)
            }

            // Desencolar lo aplicado —los triggers acaban de encolarlo— salvo lo
            // que precisamente hay que subir.
            let dequeue = Set(applied).subtracting(needsUpload)
            if !dequeue.isEmpty {
                _ = try PendingSyncChange.filter(keys: Array(dequeue)).deleteAll(db)
            }

            return needsUpload
        }
    }

    /// Otro elemento vivo con el mismo contenido. Es lo que choca contra
    /// `clipboardItem_hash_unique` al sincronizar.
    private static func liveDuplicate(
        _ db: Database,
        of item: ClipboardItem
    ) throws -> ClipboardItem? {
        try ClipboardItem
            .filter(ClipboardItem.Columns.contentHash == item.contentHash)
            .filter(ClipboardItem.Columns.deletedAt == nil)
            .filter(ClipboardItem.Columns.id != item.id.uuidString)
            .fetchOne(db)
    }

    /// Estado serializado de `CKSyncEngine`. `nil` la primera vez.
    public func syncEngineState() throws -> Data? {
        try db.reader.read { db in
            try SyncEngineState.fetchOne(db, key: 1)?.state
        }
    }

    public func setSyncEngineState(_ state: Data?) throws {
        try db.writer.write { db in
            try SyncEngineState(state: state).save(db)
        }
    }

    /// Campos de sistema del `CKRecord` de una fila, si ya se sincronizó alguna vez.
    public func recordSystemFields(for recordName: String) throws -> Data? {
        try db.reader.read { db in
            try CKRecordMetadata.fetchOne(db, key: recordName)?.systemFields
        }
    }

    public func setRecordSystemFields(
        _ systemFields: Data,
        for recordName: String,
        in table: SyncTable
    ) throws {
        try db.writer.write { db in
            try CKRecordMetadata(
                recordName: recordName,
                tableName: table,
                systemFields: systemFields
            ).save(db)
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

    /// Consulta única de la que salen el listado, la búsqueda puntual y la
    /// observación en vivo.
    ///
    /// Tenerla en un solo sitio es lo que garantiza que el panel busque
    /// exactamente sobre lo mismo que lista: cuando estaban separadas, solo el
    /// camino de búsqueda sabía unirse al índice FTS.
    static func request(
        query: String,
        filter: HistoryFilter,
        limit: Int
    ) -> QueryInterfaceRequest<ClipboardItem> {
        let base = baseRequest(filter)

        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            // Consulta vacía, o solo con signos que no producen ningún término:
            // equivale a no buscar. Si devolviera nada, escribir un espacio
            // vaciaría la pantalla.
            return applyOrdering(base, scope: filter.scope).limit(limit)
        }

        // El `MATCH` va contra la tabla FTS, no contra `clipboardItem`, así que
        // hay que unirlas por rowid en vez de filtrar directamente.
        let ftsAlias = TableAlias<ClipboardItemFTS>()
        let match = ClipboardItem.fts.aliased(ftsAlias).matching(pattern)

        // Al buscar manda la relevancia de FTS5 (`rank`), no la fecha: interesa
        // el mejor resultado, no el más reciente.
        return base
            .joining(required: match)
            .order(ftsAlias[Column.rank])
            .limit(limit)
    }

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

    /// Punto medio entre dos vecinos, o un paso más allá si solo hay uno.
    ///
    /// Es lo que permite reordenar tocando una sola fila: en vez de renumerar
    /// del 1 al n, el elemento movido se queda con un valor intermedio.
    static func fractionalOrder(after: Double?, before: Double?) -> Double {
        switch (after, before) {
        case let (lo?, hi?): return (lo + hi) / 2
        case let (lo?, nil): return lo + 1
        case let (nil, hi?): return hi - 1
        case (nil, nil): return 0
        }
    }

    private static func livePinboards() -> QueryInterfaceRequest<Pinboard> {
        Pinboard
            .filter(Pinboard.Columns.deletedAt == nil)
            .order(Pinboard.Columns.sortOrder)
    }

    private static func nextPinboardSortOrder(_ db: Database) throws -> Double {
        let maxOrder = try Double.fetchOne(
            db,
            livePinboards().select(max(Pinboard.Columns.sortOrder))
        )
        return (maxOrder ?? 0) + 1
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
