import CloudKit
import Foundation
import GRDB

/// Sincroniza la base local con la base privada de iCloud del usuario.
///
/// Se apoya en `CKSyncEngine`, que ya resuelve el estado, los lotes, los
/// reintentos, el backoff y la suscripción de push. Aquí queda lo propio de
/// Paste: qué se sube, cómo se traduce y quién gana un conflicto.
///
/// Toda la lógica delicada —quién gana, cómo converge un duplicado— vive en
/// `SyncReconciler` y en `ClipboardStore.applyRemote`, que se prueban sin red.
/// Este tipo es el pegamento.
public actor CloudSyncEngine {
    /// Qué está haciendo la sincronización, para poder enseñarlo.
    ///
    /// Sin estado visible, una sync rota es indistinguible de una sync ociosa.
    public enum Status: Equatable, Sendable {
        case detenida
        case sincronizando
        case alDia(Date)
        case fallo(String)
    }

    private let store: ClipboardStore
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let codec: CloudRecordCodec

    private var engine: CKSyncEngine?
    private var queueWatcher: Task<Void, Never>?
    private var onStatus: (@Sendable (Status) -> Void)?

    private(set) var status: Status = .detenida {
        didSet { onStatus?(status) }
    }

    public init(
        store: ClipboardStore,
        containerID: String = "iCloud.dev.threedots.paste",
        zoneName: String = "PasteZone"
    ) {
        self.store = store
        self.container = CKContainer(identifier: containerID)
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.codec = CloudRecordCodec(
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        )
    }

    public func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        onStatus = handler
        handler(status)
    }

    // MARK: - Ciclo de vida

    public func start() throws {
        guard engine == nil else { return }

        let serialized = try store.syncEngineState()
        let state = serialized.flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // La primera vez hay que crear la zona. Es propia y no la por defecto
        // porque sin zona propia no hay `fetchChanges` por zona.
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }

        status = .sincronizando
        enqueuePending()
        watchQueue()
    }

    public func stop() {
        queueWatcher?.cancel()
        queueWatcher = nil
        engine = nil
        status = .detenida
    }

    /// Encola lo que los triggers dejaron pendiente y despierta al motor en
    /// cuanto aparezca algo nuevo.
    private func watchQueue() {
        queueWatcher = Task { [weak self] in
            guard let self else { return }
            do {
                for try await pending in self.store.observePendingChanges() {
                    guard !Task.isCancelled else { return }
                    await self.enqueue(pending)
                }
            } catch is CancellationError {
                return
            } catch {
                await self.report(error)
            }
        }
    }

    private func enqueuePending() {
        guard let pending = try? store.pendingChanges() else { return }
        enqueue(pending)
    }

    private func enqueue(_ pending: [PendingSyncChange]) {
        guard let engine, !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending.map {
            .saveRecord(CKRecord.ID(recordName: $0.recordName, zoneID: zoneID))
        })
    }

    private func report(_ error: any Error) {
        status = .fallo(String(describing: error))
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            // El estado se guarda en la misma base que los datos: si se
            // perdiera, el motor volvería a bajarlo todo creyendo que empieza.
            try? store.setSyncEngineState(
                try? JSONEncoder().encode(update.stateSerialization)
            )

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes)

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)

        case .willFetchChanges, .willSendChanges:
            status = .sincronizando

        case .didFetchChanges, .didSendChanges:
            status = .alDia(Date())

        case .accountChange(let change):
            handleAccountChange(change)

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [store, codec] id in
            guard let uuid = UUID(uuidString: id.recordName) else { return nil }
            let systemFields = try? store.recordSystemFields(for: id.recordName)

            if let item = try? store.item(id: uuid) {
                // Devolver `nil` descarta el cambio: es lo que pasa con un
                // elemento demasiado grande para un `CKRecord`, que se queda en
                // local en vez de fallar la subida una y otra vez.
                return codec.record(for: item, systemFields: systemFields)
            }
            if let pinboard = try? store.pinboards().first(where: { $0.id == uuid }) {
                return codec.record(for: pinboard, systemFields: systemFields)
            }
            if let device = try? store.devices().first(where: { $0.id == uuid }) {
                return codec.record(for: device, systemFields: systemFields)
            }
            return nil
        }
    }

    // MARK: - Bajada

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        var batch = RemoteBatch()
        for modification in changes.modifications {
            codec.add(modification.record, to: &batch)
        }
        batch.deletedRecordNames = changes.deletions.map(\.recordID.recordName)

        guard !batch.items.isEmpty
                || !batch.pinboards.isEmpty
                || !batch.devices.isEmpty
                || !batch.deletedRecordNames.isEmpty
        else { return }

        do {
            // La reconciliación entera ocurre en una sola transacción, que es lo
            // que garantiza que aplicar un cambio remoto no lo reencole.
            let needsUpload = try store.applyRemote(batch)

            for modification in changes.modifications {
                try? store.setRecordSystemFields(
                    CloudRecordCodec.systemFields(of: modification.record),
                    for: modification.record.recordID.recordName,
                    in: table(of: modification.record)
                )
            }

            if !needsUpload.isEmpty, let engine {
                engine.state.add(pendingRecordZoneChanges: needsUpload.map {
                    .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID))
                })
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Subida

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        for record in sent.savedRecords {
            try? store.setRecordSystemFields(
                CloudRecordCodec.systemFields(of: record),
                for: record.recordID.recordName,
                in: table(of: record)
            )
        }
        try? store.clearPending(recordNames: sent.savedRecords.map(\.recordID.recordName))

        for failure in sent.failedRecordSaves {
            switch failure.error.code {
            case .serverRecordChanged:
                // El servidor tiene una versión más nueva. Se aplica por el
                // camino normal, que es el que sabe quién gana.
                if let server = failure.error.serverRecord {
                    var batch = RemoteBatch()
                    codec.add(server, to: &batch)
                    try? store.setRecordSystemFields(
                        CloudRecordCodec.systemFields(of: server),
                        for: server.recordID.recordName,
                        in: table(of: server)
                    )
                    _ = try? store.applyRemote(batch)
                }

            case .zoneNotFound, .userDeletedZone:
                // Alguien borró la zona desde otro sitio: se rehace y se vuelve
                // a subir todo lo que hay.
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                enqueuePending()

            case .unknownItem:
                // El registro ya no existe en el servidor. Se olvidan sus campos
                // de sistema para que la próxima subida lo cree de cero.
                try? store.clearPending(recordNames: [failure.record.recordID.recordName])

            default:
                report(failure.error)
            }
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            enqueuePending()
        case .signOut, .switchAccounts:
            // No se borra nada en local: el historial es del usuario, no de la
            // cuenta de iCloud. Solo se deja de sincronizar.
            stop()
        @unknown default:
            break
        }
    }

    private nonisolated func table(of record: CKRecord) -> SyncTable {
        switch record.recordType {
        case CloudRecordCodec.RecordType.pinboard: .pinboard
        case CloudRecordCodec.RecordType.device: .device
        default: .clipboardItem
        }
    }
}
