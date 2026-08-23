import AppKit
import ApplicationServices

/// Permiso de Accesibilidad, que es lo que autoriza a sintetizar pulsaciones.
///
/// Sin él la app sigue siendo útil: el panel copia al portapapeles y el usuario
/// pega a mano. El Direct Paste es lo único que se pierde, así que en ningún
/// sitio se bloquea nada por no tenerlo.
enum AccessibilityAuthorization {
    /// Se consulta al sistema cada vez en lugar de guardarlo: el permiso se
    /// concede y se retira desde Ajustes, sin avisar a la app, y un valor
    /// cacheado dejaría el menú mintiendo hasta el siguiente arranque.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pide el permiso mostrando la alerta del sistema.
    ///
    /// Devuelve el estado actual, que será `false` recién pedido: conceder el
    /// permiso ocurre en Ajustes, en otro momento, no dentro de esta llamada.
    @discardableResult
    static func request() -> Bool {
        // La clave va escrita a mano: `kAXTrustedCheckOptionPrompt` es una
        // global mutable de C y Swift 6 no la deja leer desde código
        // concurrente. Su valor es esta cadena y forma parte de la API.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Abre el panel de Ajustes donde se marca la casilla.
    ///
    /// La alerta del sistema solo aparece la primera vez; después, quien haya
    /// dicho que no se queda sin camino de vuelta si no se le ofrece este.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
