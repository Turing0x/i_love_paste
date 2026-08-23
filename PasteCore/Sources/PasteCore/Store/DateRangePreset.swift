import Foundation

/// Rangos de fecha ofrecidos en la barra de filtros.
///
/// Son presets y no un selector de fechas libre porque, buscando algo que
/// copiaste, casi nunca recuerdas el día: recuerdas si fue hoy o hace un par de
/// semanas.
public enum DateRangePreset: String, CaseIterable, Sendable {
    case any
    case today
    case last7Days
    case last30Days

    public var label: String {
        switch self {
        case .any: "Cualquier fecha"
        case .today: "Hoy"
        case .last7Days: "Últimos 7 días"
        case .last30Days: "Últimos 30 días"
        }
    }

    /// Aplica el rango sobre un filtro existente, respetando el resto de sus
    /// criterios.
    public func applied(
        to filter: HistoryFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HistoryFilter {
        var filter = filter
        filter.createdAfter = start(now: now, calendar: calendar)
        return filter
    }

    func start(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .any:
            nil
        case .today:
            // Desde el comienzo del día, no desde hace 24 horas: "hoy" a las
            // nueve de la mañana no debe incluir lo de ayer por la tarde.
            calendar.startOfDay(for: now)
        case .last7Days:
            calendar.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            calendar.date(byAdding: .day, value: -30, to: now)
        }
    }
}
