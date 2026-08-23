import SwiftUI

/// Colores disponibles para un pinboard.
///
/// Es una paleta cerrada y no una rueda de color por dos razones: cualquier
/// selector de color de macOS es una ventana aparte, y este panel se cierra en
/// cuanto pierde el foco; y una paleta elegida a mano garantiza que el punto de
/// color se distinga sobre el material del panel en claro y en oscuro.
enum PinboardColor {
    /// Los colores del sistema, en el orden en que los muestra macOS.
    static let palette: [(name: String, hex: String)] = [
        ("Rojo", "FF3B30"),
        ("Naranja", "FF9500"),
        ("Amarillo", "FFCC00"),
        ("Verde", "34C759"),
        ("Azul", "007AFF"),
        ("Morado", "AF52DE"),
        ("Rosa", "FF2D55"),
        ("Gris", "8E8E93")
    ]

    /// Convierte un `RRGGBB` en color. Un valor ilegible cae en gris en vez de
    /// desaparecer: un pinboard sin punto parecería un fallo de pintado.
    static func color(hex: String) -> Color {
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value), hex.count == 6 else {
            return Color(.systemGray)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
