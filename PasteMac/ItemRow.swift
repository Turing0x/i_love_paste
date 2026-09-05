import AppKit
import PasteCore
import SwiftUI

/// Una fila del historial.
struct ItemRow: View {
    let item: ClipboardItem
    let icon: NSImage?
    /// Número de Quick Paste, si el elemento está entre los nueve primeros.
    let quickPasteNumber: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(item.sourceAppName ?? "Origen desconocido")
                    Text("·")
                    Text(item.createdAt, format: .relative(presentation: .numeric))
                }
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            // Mostrar el número hace que Quick Paste se descubra solo, sin
            // tener que leer ninguna documentación.
            if let quickPasteNumber {
                Text("⌘\(quickPasteNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : .clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // La selección se enseña con el fondo de acento y nada más: sin el
        // rasgo, quien navega con VoiceOver no sabe dónde está el cursor.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Tipo, contenido, procedencia y atajo, en una frase.
    ///
    /// El "⌘1" se deletrea: leído tal cual suena a ruido.
    private var accessibilityLabel: String {
        let origen = item.sourceAppName ?? "origen desconocido"
        var texto = "\(item.kind.label): \(item.displayTitle). De \(origen)"
        if let quickPasteNumber {
            texto += ". Atajo Comando \(quickPasteNumber)"
        }
        return texto
    }
}

extension SkipReason {
    /// Por qué no se guardó lo último que se copió, en una frase.
    ///
    /// Lo enseña el pie del panel. Sin esto, la pausa y las exclusiones son
    /// indistinguibles de un fallo: se copia algo, no aparece, y no hay nada
    /// que mirar.
    var explanation: String {
        switch self {
        case .unchanged, .empty: ""
        case .concealed: "Último copiado omitido: contenido protegido"
        case .transient: "Último copiado omitido: contenido temporal"
        case .paused: "Captura en pausa"
        case .excludedApp: "Último copiado omitido: app excluida"
        case .unsupportedType: "Último copiado omitido: tipo no soportado todavía"
        case .tooLarge: "Último copiado omitido: demasiado grande"
        }
    }
}
