import AppIntents
import PasteCore

/// Qué lista enseña el widget (§38): el historial, o un pinboard concreto.
struct ScopeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lista"
    static let description = IntentDescription(
        "Elige si el widget enseña el historial reciente o un pinboard."
    )

    /// Vacío significa historial. Un opcional evita tener que inventar una
    /// entidad falsa para representarlo.
    @Parameter(title: "Pinboard")
    var pinboard: PinboardEntity?

    init() {}

    init(pinboard: PinboardEntity?) {
        self.pinboard = pinboard
    }
}

/// Un pinboard, tal como lo ofrece el selector del widget.
struct PinboardEntity: AppEntity {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pinboard"
    static let defaultQuery = PinboardQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Lee los pinboards vivos de la base compartida.
///
/// Reutiliza `ClipboardStore.pinboards()`, que ya filtra las lápidas y respeta
/// el orden manual.
struct PinboardQuery: EntityQuery {
    func entities(for identifiers: [UUID]) throws -> [PinboardEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() throws -> [PinboardEntity] {
        try all()
    }

    private func all() throws -> [PinboardEntity] {
        let store = try WidgetStore.open()
        return try store.pinboards().map { PinboardEntity(id: $0.id, name: $0.name) }
    }
}

/// Abre la base del grupo compartido en modo lectura.
///
/// El widget y su selector son procesos aparte de la app, así que abren su
/// propia conexión. No escriben nada.
enum WidgetStore {
    static func open() throws -> ClipboardStore {
        let url = try AppPaths.databaseURL(appGroup: AppPaths.sharedGroupIdentifier)
        return ClipboardStore(try AppDatabase.open(at: url))
    }
}
