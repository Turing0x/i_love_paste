import Foundation
import GRDB

/// Colección permanente de elementos. A diferencia del historial, su contenido
/// no caduca con la política de retención.
public struct Pinboard: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    /// Color en formato `RRGGBB` sin almohadilla.
    public var colorHex: String

    /// Orden fraccional en la lista lateral.
    public var sortOrder: Double

    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = Pinboard.defaultColorHex,
        sortOrder: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Gris del sistema. El color es decoración, así que un pinboard recién
    /// creado tiene que verse bien sin que nadie elija nada.
    public static let defaultColorHex = "8E8E93"
}

extension Pinboard: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pinboard"

    /// Los UUID se guardan como texto en mayúsculas, no como el BLOB de 16
    /// bytes que GRDB usa por omisión: las consultas filtran por `uuidString`,
    /// y una base cuyos identificadores se leen con `sqlite3` vale mucho más a
    /// la hora de depurar.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    public enum Columns {
        public static let id = Column("id")
        public static let name = Column("name")
        public static let colorHex = Column("colorHex")
        public static let sortOrder = Column("sortOrder")
        public static let updatedAt = Column("updatedAt")
        public static let deletedAt = Column("deletedAt")
    }

    public static let items = hasMany(ClipboardItem.self, using: ForeignKey(["pinboardID"]))
}
