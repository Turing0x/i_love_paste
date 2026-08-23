import Foundation
import GRDB

public enum DevicePlatform: String, Codable, Sendable {
    case macOS
    case iOS
    case iPadOS
}

/// Dispositivo que ha aportado elementos. Se usa para filtrar por origen y,
/// cuando llegue la sincronización, para desempatar conflictos.
public struct Device: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var platform: DevicePlatform
    public var lastSeenAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        platform: DevicePlatform,
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeenAt = lastSeenAt
    }
}

extension Device: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "device"

    /// Los UUID se guardan como texto en mayúsculas, no como el BLOB de 16
    /// bytes que GRDB usa por omisión: las consultas filtran por `uuidString`,
    /// y una base cuyos identificadores se leen con `sqlite3` vale mucho más a
    /// la hora de depurar.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
}
