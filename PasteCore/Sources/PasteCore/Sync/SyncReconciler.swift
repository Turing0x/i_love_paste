import Foundation

/// Qué versión de una fila sobrevive.
public enum SyncSide: Equatable, Sendable {
    /// Gana lo que llegó del servidor: hay que guardarlo encima de lo local.
    case remote
    /// Gana lo local: no se toca nada y la fila se vuelve a subir.
    case local
}

/// Fila que sabe resolver sus propios conflictos.
public protocol SyncReconcilable {
    var updatedAt: Date { get }

    /// Huella del contenido, para desempatar cuando `updatedAt` coincide.
    ///
    /// Tiene que depender solo del contenido, nunca del dispositivo ni de la
    /// hora local: es exactamente lo que garantiza que los dos lados calculen el
    /// mismo desempate por separado.
    var syncFingerprint: String { get }
}

/// Decide qué versión de cada fila sobrevive, sin tocar CloudKit ni la red.
///
/// Va aparte del motor por el mismo motivo que `CaptureEngine` recibe una
/// `PasteboardSnapshot` ya extraída en vez de leer el portapapeles: así toda la
/// lógica que puede estar mal se prueba entera con datos inventados.
public enum SyncReconciler {
    /// Último en escribir gana.
    ///
    /// El empate no se resuelve prefiriendo el servidor: cada dispositivo llama
    /// "remoto" a la versión del otro, así que esa regla los haría intercambiarse
    /// la fila indefinidamente. Se desempata por huella de contenido, que ambos
    /// calculan igual y les lleva al mismo sitio sin hablarse.
    public static func resolve<T: SyncReconcilable>(local: T?, remote: T) -> SyncSide {
        guard let local else { return .remote }

        if remote.updatedAt > local.updatedAt { return .remote }
        if remote.updatedAt < local.updatedAt { return .local }

        return remote.syncFingerprint > local.syncFingerprint ? .remote : .local
    }

    /// Resuelve dos elementos vivos con el mismo `contentHash` y distinto `id`.
    ///
    /// Ocurre al copiar el mismo texto en los dos dispositivos estando sin red:
    /// salen dos filas legítimas, y al sincronizar la segunda choca contra
    /// `clipboardItem_hash_unique`, que es único sobre los vivos.
    ///
    /// Sobrevive el `id` menor —deterministic en ambos lados— con la fecha de
    /// copia más reciente de las dos, que es lo que ya hace `capture` al ascender
    /// un duplicado. El otro recibe lápida en vez de desaparecer, para que el
    /// dispositivo que lo creó se entere de que dejó de existir.
    public static func resolveDuplicate(
        _ one: ClipboardItem,
        _ other: ClipboardItem,
        at now: Date = Date()
    ) -> (winner: ClipboardItem, loser: ClipboardItem) {
        let ordered = [one, other].sorted { $0.id.uuidString < $1.id.uuidString }
        var winner = ordered[0]
        var loser = ordered[1]

        winner.createdAt = max(one.createdAt, other.createdAt)
        winner.updatedAt = now

        loser.deletedAt = now
        loser.updatedAt = now

        return (winner, loser)
    }
}

// MARK: - Huellas

extension ClipboardItem: SyncReconcilable {
    public var syncFingerprint: String {
        [
            contentHash,
            title ?? "",
            pinboardID?.uuidString ?? "",
            String(sortOrder),
            deletedAt == nil ? "vivo" : "lápida"
        ].joined(separator: "|")
    }
}

extension Pinboard: SyncReconcilable {
    public var syncFingerprint: String {
        [
            name,
            colorHex,
            String(sortOrder),
            deletedAt == nil ? "vivo" : "lápida"
        ].joined(separator: "|")
    }
}

extension Device: SyncReconcilable {
    /// El registro de dispositivo no tiene `updatedAt` propio: lo que se mueve
    /// es `lastSeenAt`, y es lo que decide quién manda.
    public var updatedAt: Date { lastSeenAt }

    public var syncFingerprint: String { "\(name)|\(platform.rawValue)" }
}
