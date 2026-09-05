import Foundation

/// Traduce la posición donde se suelta un arrastre al hueco entre vecinos que
/// entiende el orden fraccional.
///
/// Vive aparte y sin depender de ningún modelo concreto porque el cálculo es el
/// mismo para elementos y para pinboards, y porque es justo donde estaba el
/// fallo: la lista que ve el usuario **incluye** el elemento arrastrado, pero
/// los vecinos hay que buscarlos en la lista **sin** él. Al quitarlo, todo lo
/// que venía detrás baja una posición, y no descontarla mandaba cada arrastre
/// hacia abajo un puesto más allá de donde se soltó.
public enum ReorderPlan {
    /// Los dos vecinos entre los que cae el elemento. `nil` en un extremo
    /// significa que no hay nadie por ese lado.
    public struct Neighbours: Equatable, Sendable {
        public var after: Double?
        public var before: Double?

        public init(after: Double?, before: Double?) {
            self.after = after
            self.before = before
        }
    }

    /// - Parameters:
    ///   - id: elemento que se está moviendo.
    ///   - index: posición **en `rows`** ante la que se suelta, o `nil` para el
    ///     final. Es lo que dan tanto `onMove` como `dropDestination`, los dos
    ///     en coordenadas de la lista visible.
    ///   - rows: la lista tal como se ve, con el arrastrado dentro.
    /// - Returns: los vecinos, o `nil` si el movimiento no lleva a ninguna parte
    ///   (elemento desconocido, o lista de un solo elemento).
    public static func neighbours(
        moving id: UUID,
        before index: Int?,
        in rows: [(id: UUID, sortOrder: Double)]
    ) -> Neighbours? {
        guard let from = rows.firstIndex(where: { $0.id == id }) else { return nil }

        let others = rows.enumerated()
            .filter { $0.offset != from }
            .map(\.element)

        // El propio arrastrado ya no cuenta: soltarlo delante de algo que está
        // detrás de él deja un hueco menos por el camino.
        var target = index ?? others.count
        if let index, index > from { target -= 1 }
        target = min(max(target, 0), others.count)

        let after = target > 0 ? others[target - 1].sortOrder : nil
        let before = target < others.count ? others[target].sortOrder : nil
        guard after != nil || before != nil else { return nil }

        return Neighbours(after: after, before: before)
    }
}
