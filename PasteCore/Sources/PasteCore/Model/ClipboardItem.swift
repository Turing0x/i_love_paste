import Foundation
import GRDB

/// Un elemento capturado del portapapeles.
///
/// Los campos `updatedAt`, `deletedAt` y `sourceDeviceID` existen desde la
/// primera versión aunque la sincronización no esté implementada: añadirlos
/// después obligaría a migrar y reconciliar toda la base de datos.
public struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID

    /// SHA-256 del contenido normalizado. Base de la deduplicación: recopiar
    /// lo mismo actualiza el elemento existente en vez de crear otra fila.
    public var contentHash: String

    public var kind: ContentKind

    /// Texto plano del elemento. Es lo que se indexa en FTS5, y para `image` y
    /// `file` se rellena con lo que haya (nombre de fichero, texto de OCR más
    /// adelante) para que sigan siendo buscables.
    public var plainText: String?

    /// Representación con formato (RTF). Solo para `kind == .richText`.
    public var richData: Data?

    /// Ruta relativa dentro del directorio de blobs, con forma `ab/cdef...`.
    /// Solo para tipos con `isBlobBacked`.
    public var blobPath: String?

    /// Tamaño en bytes del contenido, para mostrar y para políticas de retención.
    public var byteSize: Int

    /// Título puesto a mano por el usuario. `nil` = usar el derivado del contenido.
    public var title: String?

    public var sourceBundleID: String?
    public var sourceAppName: String?

    /// Host de la URL, almacenado aparte para poder buscar "github" y encontrar
    /// enlaces cuyo texto visible no contiene esa palabra. Es columna real y no
    /// propiedad calculada porque el índice FTS5 con contenido externo solo
    /// puede indexar columnas que existan en la tabla.
    public var urlHost: String?

    /// Dispositivo donde se capturó. Necesario para filtrar por origen y para
    /// desempatar conflictos cuando llegue la sincronización.
    public var sourceDeviceID: UUID

    public var createdAt: Date
    public var updatedAt: Date

    /// Lápida. Los borrados no son físicos: sin esto, un borrado en el Mac
    /// reaparecería al sincronizar con el iPhone.
    public var deletedAt: Date?

    public var pinboardID: UUID?

    /// Orden fraccional dentro de su pinboard: reordenar solo reescribe la fila
    /// movida, no toda la tabla.
    public var sortOrder: Double

    public init(
        id: UUID = UUID(),
        contentHash: String,
        kind: ContentKind,
        plainText: String? = nil,
        richData: Data? = nil,
        blobPath: String? = nil,
        byteSize: Int = 0,
        title: String? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        urlHost: String? = nil,
        sourceDeviceID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        pinboardID: UUID? = nil,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kind = kind
        self.plainText = plainText
        self.richData = richData
        self.blobPath = blobPath
        self.byteSize = byteSize
        self.title = title
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.urlHost = urlHost ?? (kind == .url ? Self.extractHost(from: plainText) : nil)
        self.sourceDeviceID = sourceDeviceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.pinboardID = pinboardID
        self.sortOrder = sortOrder
    }

    /// Título a mostrar: el manual si existe, si no uno derivado del contenido.
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        guard let plainText else { return kind.rawValue }
        let firstLine = plainText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? kind.rawValue : firstLine
    }

    static func extractHost(from text: String?) -> String? {
        guard let text else { return nil }
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
    }
}

extension ClipboardItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "clipboardItem"

    /// Los UUID se guardan como texto en mayúsculas, no como el BLOB de 16
    /// bytes que GRDB usa por omisión: las consultas filtran por `uuidString`,
    /// y una base cuyos identificadores se leen con `sqlite3` vale mucho más a
    /// la hora de depurar.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    public enum Columns {
        public static let id = Column("id")
        public static let contentHash = Column("contentHash")
        public static let kind = Column("kind")
        public static let plainText = Column("plainText")
        public static let title = Column("title")
        public static let sourceBundleID = Column("sourceBundleID")
        public static let sourceDeviceID = Column("sourceDeviceID")
        public static let createdAt = Column("createdAt")
        public static let updatedAt = Column("updatedAt")
        public static let deletedAt = Column("deletedAt")
        public static let pinboardID = Column("pinboardID")
        public static let sortOrder = Column("sortOrder")
    }
}

/// Espejo del índice FTS5. No se lee nunca directamente: existe solo para poder
/// expresar la unión por rowid en las búsquedas.
public enum ClipboardItemFTS: TableRecord {
    public static let databaseTableName = "clipboardItem_fts"
}

extension ClipboardItem {
    /// Unión con el índice de búsqueda. `synchronize(withTable:)` mantiene el
    /// rowid de ambas tablas alineado, y esa es la clave de la relación.
    public static let fts = hasOne(
        ClipboardItemFTS.self,
        using: ForeignKey(["rowid"], to: ["rowid"])
    )
}
