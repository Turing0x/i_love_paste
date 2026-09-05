import PasteCore
import SwiftUI

/// Una fila del historial en iOS.
///
/// Gemela de la del Mac sin el icono de la app de origen: en iOS no hay forma de
/// obtener el icono de otra aplicación, así que se queda solo su nombre.
struct ItemRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(item.sourceAppName ?? "Origen desconocido")
                    Text("·")
                    Text(item.createdAt, format: .relative(presentation: .numeric))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Empuja hacia la izquierda: las acciones de la fila se colocan
            // después de esta vista y tienen que quedar pegadas al borde.
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        // Sin esto VoiceOver lee cuatro elementos sueltos —icono, título, app,
        // fecha— y hay que pasar por los cuatro para llegar al siguiente
        // elemento del historial. Junta lee una fila, que es lo que es.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Toca dos veces para copiar")
    }

    /// Tipo, contenido y procedencia en una frase.
    ///
    /// El tipo entra explícito porque en pantalla lo dice un símbolo, y el
    /// símbolo no se lee.
    private var accessibilityLabel: String {
        let origen = item.sourceAppName ?? "origen desconocido"
        return "\(item.kind.label): \(item.displayTitle). De \(origen)"
    }
}
