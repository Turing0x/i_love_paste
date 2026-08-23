import Foundation

/// Posición seleccionada dentro de una lista.
///
/// Es lógica pura y vive aquí, y no en la app, para poder probarla: los fallos
/// de navegación por teclado son de los que solo se notan usando la herramienta,
/// cuando ya es tarde.
public struct SelectionCursor: Equatable, Sendable {
    public private(set) var index: Int

    public init(index: Int = 0) {
        self.index = max(0, index)
    }

    /// Mueve la selección sujetándola a los extremos, **sin dar la vuelta**.
    ///
    /// Reaparecer arriba al mantener pulsada la flecha abajo desorienta: cuando
    /// se llega al final, lo que se espera es quedarse ahí.
    public func moved(by delta: Int, count: Int) -> SelectionCursor {
        guard count > 0 else { return SelectionCursor(index: 0) }
        return SelectionCursor(index: min(max(index + delta, 0), count - 1))
    }

    /// Recoloca la selección dentro de una lista que puede haber cambiado de
    /// tamaño.
    ///
    /// Hace falta porque la lista se rehace bajo los pies mientras se escribe en
    /// el buscador, y el índice que era válido con veinte resultados deja de
    /// serlo con tres.
    public func clamped(to count: Int) -> SelectionCursor {
        guard count > 0 else { return SelectionCursor(index: 0) }
        return SelectionCursor(index: min(index, count - 1))
    }

    /// Elemento seleccionado, o `nil` si la lista está vacía.
    public func selected<T>(in items: [T]) -> T? {
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }
}
