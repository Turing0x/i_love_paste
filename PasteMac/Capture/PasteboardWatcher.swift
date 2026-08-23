import AppKit
import Foundation
import PasteCore

/// Sondea el portapapeles y guarda lo que merezca la pena.
///
/// macOS no notifica los cambios del portapapeles: no hay ninguna API de
/// observación, así que sondear es la única vía. 300 ms es el equilibrio
/// habitual entre notarlo al instante y no despertar la CPU sin parar.
@MainActor
@Observable
final class PasteboardWatcher {
    private let reader: NSPasteboardSnapshotReader
    private let store: ClipboardStore
    private var engine: CaptureEngine
    private var timer: Timer?

    /// Último contador ya evaluado. Avanza tras **cada** evaluación, se capture
    /// o no.
    private var lastChangeCount: Int

    /// Contador de una escritura hecha por nosotros mismos.
    ///
    /// Sin esto, devolver un elemento al portapapeles dispararía nuestro propio
    /// vigilante, que lo detectaría como contenido nuevo y lo recapturaría.
    private var selfWriteChangeCount: Int?

    /// Último descarte, para poder responder a "¿por qué no se ha guardado
    /// esto?".
    private(set) var lastSkip: SkipReason?

    init(store: ClipboardStore, settings: CaptureSettings, deviceID: UUID) {
        self.store = store
        self.engine = CaptureEngine(settings: settings, deviceID: deviceID)
        self.reader = NSPasteboardSnapshotReader()
        // Se arranca desde el estado actual: lo que ya estuviera copiado antes
        // de abrir la app no es algo que el usuario acabe de hacer.
        self.lastChangeCount = reader.changeCount
    }

    var settings: CaptureSettings {
        get { engine.settings }
        set { engine.settings = newValue }
    }

    func start(interval: TimeInterval = 0.3) {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Deja que el sistema agrupe los despertares con otros ya programados,
        // que es lo que evita que sondear cada 300 ms castigue la batería.
        timer.tolerance = interval / 3
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Marca un contador como escritura propia, para no recapturar lo que
    /// acabamos de poner nosotros en el portapapeles.
    func ignoreChange(_ changeCount: Int) {
        selfWriteChangeCount = changeCount
    }

    private func tick() {
        let current = reader.changeCount
        guard current != lastChangeCount else { return }

        if current == selfWriteChangeCount {
            selfWriteChangeCount = nil
            lastChangeCount = current
            return
        }

        let decision = engine.decide(
            reader.snapshot(),
            lastChangeCount: lastChangeCount,
            frontmost: reader.frontmostApp()
        )

        // El contador avanza pase lo que pase. Es lo que hace que la pausa, las
        // exclusiones y el contenido oculto se comporten igual sin casos
        // especiales: al reanudar tras una pausa no se recupera lo copiado
        // durante ella, porque ya se dio por evaluado.
        lastChangeCount = current

        switch decision {
        case .capture(let item):
            lastSkip = nil
            do {
                try store.capture(item)
            } catch {
                NSLog("Paste: no se pudo guardar el elemento: \(error)")
            }
        case .skip(let reason):
            lastSkip = reason
        }
    }
}
