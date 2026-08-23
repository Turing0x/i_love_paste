import Foundation

/// Criterios de filtrado del historial. Se combinan entre sí y con el texto de
/// búsqueda; todos los campos vacíos significan "sin restricción".
public struct HistoryFilter: Equatable, Sendable {
    public var kinds: Set<ContentKind>
    public var bundleIDs: Set<String>
    public var deviceIDs: Set<UUID>
    public var createdAfter: Date?
    public var createdBefore: Date?

    /// Ámbito: historial suelto, un pinboard concreto, o todo junto.
    public enum Scope: Equatable, Sendable {
        /// Elementos que no están en ningún pinboard.
        case history
        case pinboard(UUID)
        case everything
    }

    public var scope: Scope

    public init(
        scope: Scope = .history,
        kinds: Set<ContentKind> = [],
        bundleIDs: Set<String> = [],
        deviceIDs: Set<UUID> = [],
        createdAfter: Date? = nil,
        createdBefore: Date? = nil
    ) {
        self.scope = scope
        self.kinds = kinds
        self.bundleIDs = bundleIDs
        self.deviceIDs = deviceIDs
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
    }

    public static let history = HistoryFilter()
}
