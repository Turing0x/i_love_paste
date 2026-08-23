import CloudKit
import Foundation

/// Traduce entre las filas de la base y los `CKRecord`.
///
/// Está separado del motor para que el motor solo se ocupe del protocolo de
/// sincronización y esto solo del formato de los datos.
struct CloudRecordCodec: Sendable {
    let zoneID: CKRecordZone.ID

    enum RecordType {
        static let clipboardItem = "ClipboardItem"
        static let pinboard = "Pinboard"
        static let device = "Device"
    }

    /// Tope por registro. CloudKit admite 1 MB de campos no-asset; se deja
    /// margen para las claves y los campos de sistema.
    ///
    /// `maxTextBytes` permite hasta 5 MB, así que un volcado grande no cabe. Se
    /// queda en local en vez de fallar la subida en bucle; llegará con M2b, que
    /// es cuando exista `CKAsset`.
    static let maxSyncableBytes = 700_000

    // MARK: - Fila → registro

    /// `nil` si el elemento no cabe en un `CKRecord`.
    func record(for item: ClipboardItem, systemFields: Data?) -> CKRecord? {
        guard item.byteSize <= Self.maxSyncableBytes else { return nil }

        let record = makeRecord(
            recordName: item.id.uuidString,
            type: RecordType.clipboardItem,
            systemFields: systemFields
        )

        // Cifrado: todo lo que es contenido del usuario. Las claves las guarda
        // su llavero, no Apple. No se pierde nada por cifrarlo porque ninguna
        // búsqueda ocurre en servidor — FTS5 es local.
        record.encryptedValues["plainText"] = item.plainText
        record.encryptedValues["title"] = item.title
        record.encryptedValues["urlHost"] = item.urlHost
        record.encryptedValues["contentHash"] = item.contentHash
        if let richData = item.richData {
            record.encryptedValues["richData"] = richData as NSData
        }

        // En claro: metadatos sin los que el motor no puede ordenar ni filtrar.
        record["kind"] = item.kind.rawValue
        record["byteSize"] = item.byteSize
        record["sourceBundleID"] = item.sourceBundleID
        record["sourceAppName"] = item.sourceAppName
        record["sourceDeviceID"] = item.sourceDeviceID.uuidString
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt
        record["deletedAt"] = item.deletedAt
        record["pinboardID"] = item.pinboardID?.uuidString
        record["sortOrder"] = item.sortOrder

        // `blobPath` no viaja: es una ruta de este disco. El contenido de
        // imágenes y ficheros irá en un `CKAsset` cuando llegue M2b.
        return record
    }

    func record(for pinboard: Pinboard, systemFields: Data?) -> CKRecord {
        let record = makeRecord(
            recordName: pinboard.id.uuidString,
            type: RecordType.pinboard,
            systemFields: systemFields
        )
        record.encryptedValues["name"] = pinboard.name
        record["colorHex"] = pinboard.colorHex
        record["sortOrder"] = pinboard.sortOrder
        record["createdAt"] = pinboard.createdAt
        record["updatedAt"] = pinboard.updatedAt
        record["deletedAt"] = pinboard.deletedAt
        return record
    }

    func record(for device: Device, systemFields: Data?) -> CKRecord {
        let record = makeRecord(
            recordName: device.id.uuidString,
            type: RecordType.device,
            systemFields: systemFields
        )
        record.encryptedValues["name"] = device.name
        record["platform"] = device.platform.rawValue
        record["lastSeenAt"] = device.lastSeenAt
        return record
    }

    // MARK: - Registro → fila

    /// Reparte un registro bajado en el hueco que le toque del lote.
    ///
    /// Un registro que no encaja en ningún tipo conocido se ignora: puede venir
    /// de una versión más nueva de la app en el otro dispositivo, y tirar la
    /// sincronización entera por eso sería desproporcionado.
    func add(_ record: CKRecord, to batch: inout RemoteBatch) {
        switch record.recordType {
        case RecordType.clipboardItem:
            if let item = item(from: record) { batch.items.append(item) }
        case RecordType.pinboard:
            if let pinboard = pinboard(from: record) { batch.pinboards.append(pinboard) }
        case RecordType.device:
            if let device = device(from: record) { batch.devices.append(device) }
        default:
            break
        }
    }

    func item(from record: CKRecord) -> ClipboardItem? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let contentHash: String = record.encryptedValues["contentHash"] as? String,
              let kindRaw = record["kind"] as? String,
              let kind = ContentKind(rawValue: kindRaw),
              let sourceDeviceID = (record["sourceDeviceID"] as? String).flatMap(UUID.init(uuidString:)),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date
        else { return nil }

        return ClipboardItem(
            id: id,
            contentHash: contentHash,
            kind: kind,
            plainText: record.encryptedValues["plainText"] as? String,
            richData: record.encryptedValues["richData"] as? Data,
            byteSize: record["byteSize"] as? Int ?? 0,
            title: record.encryptedValues["title"] as? String,
            sourceBundleID: record["sourceBundleID"] as? String,
            sourceAppName: record["sourceAppName"] as? String,
            urlHost: record.encryptedValues["urlHost"] as? String,
            sourceDeviceID: sourceDeviceID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: record["deletedAt"] as? Date,
            pinboardID: (record["pinboardID"] as? String).flatMap(UUID.init(uuidString:)),
            sortOrder: record["sortOrder"] as? Double ?? 0
        )
    }

    func pinboard(from record: CKRecord) -> Pinboard? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record.encryptedValues["name"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date
        else { return nil }

        return Pinboard(
            id: id,
            name: name,
            colorHex: record["colorHex"] as? String ?? Pinboard.defaultColorHex,
            sortOrder: record["sortOrder"] as? Double ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: record["deletedAt"] as? Date
        )
    }

    func device(from record: CKRecord) -> Device? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record.encryptedValues["name"] as? String,
              let platform = (record["platform"] as? String).flatMap(DevicePlatform.init(rawValue:)),
              let lastSeenAt = record["lastSeenAt"] as? Date
        else { return nil }

        return Device(id: id, name: name, platform: platform, lastSeenAt: lastSeenAt)
    }

    // MARK: - Campos de sistema

    /// Los campos de sistema llevan la etiqueta de cambio: sin ella, cada subida
    /// llegaría al servidor como un conflicto contra la versión anterior de uno
    /// mismo.
    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func makeRecord(recordName: String, type: String, systemFields: Data?) -> CKRecord {
        if let systemFields,
           let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            unarchiver.requiresSecureCoding = true
            if let record = CKRecord(coder: unarchiver) {
                unarchiver.finishDecoding()
                return record
            }
        }
        return CKRecord(
            recordType: type,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
    }
}
