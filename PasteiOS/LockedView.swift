import PasteCore
import SwiftUI

/// Lo que se ve cuando la app está detrás del muro.
///
/// El historial sigue intacto en el disco: al volver a haber suscripción
/// reaparece entero, y decirlo aquí evita que nadie borre la app pensando que
/// perdió lo que tenía.
struct LockedView: View {
    let reason: LockReason

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(titulo)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(explicacion)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titulo: String {
        switch reason {
        case .never, .mirrorNeverSeen:
            "Paste necesita suscripción"
        case .expired, .mirrorStale:
            "Tu suscripción ha terminado"
        }
    }

    private var explicacion: String {
        switch reason {
        case .never, .mirrorNeverSeen:
            "Prueba Paste gratis y guarda todo lo que copias, en el iPhone y en el Mac."
        case .expired, .mirrorStale:
            "Tu historial sigue guardado. Vuelve a suscribirte para recuperarlo."
        }
    }
}
