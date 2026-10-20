import PasteCore
import SwiftUI

/// Textos del Mac bloqueado.
///
/// Viven fuera de las vistas porque los usan dos sitios —el menú de la barra y
/// el panel— y decir cosas distintas en cada uno convierte un problema con
/// solución en un misterio.
enum MacLockedCopy {
    static func title(_ reason: LockReason) -> String {
        switch reason {
        case .never, .mirrorNeverSeen:
            "Suscripción requerida"
        case .mirrorStale:
            "Sin noticias de tu iPhone"
        case .expired:
            "Tu suscripción ha terminado"
        }
    }

    /// Cada motivo se arregla de una forma distinta, y decir cuál es la única
    /// parte útil del mensaje.
    static func detail(_ reason: LockReason) -> String {
        switch reason {
        case .never, .mirrorNeverSeen:
            """
            Suscríbete desde la app de Paste en tu iPhone. Si ya lo has hecho, \
            comprueba que este Mac usa la misma cuenta de iCloud.
            """
        case .mirrorStale:
            "Abre Paste en tu iPhone para confirmar que la suscripción sigue activa."
        case .expired:
            "Vuelve a suscribirte desde la app de Paste en tu iPhone."
        }
    }
}

/// Lo que enseña el panel flotante cuando el Mac está bloqueado.
///
/// El atajo ⌥⌘V se sigue registrando y abriendo esto: un atajo que no hace nada
/// se lee como una app rota, no como una app sin suscripción.
struct MacLockedView: View {
    let reason: LockReason
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(MacLockedCopy.title(reason))
                .font(.headline)

            Text(MacLockedCopy.detail(reason))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Comprobar de nuevo", action: onRecheck)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
