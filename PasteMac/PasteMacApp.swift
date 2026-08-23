import AppKit
import PasteCore
import SwiftUI

@main
struct PasteMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        // La app no tiene ventanas: vive en la barra de menús y se usa a través
        // del panel flotante. Sin esta escena, sin icono en el Dock, no habría
        // forma de salir ni de saber que está funcionando.
        MenuBarExtra("Paste", systemImage: "doc.on.clipboard") {
            Button("Mostrar Paste") { environment.panel.show() }
                .keyboardShortcut("v", modifiers: [.option, .command])

            Divider()

            Toggle("Pausar captura", isOn: Binding(
                get: { environment.isPaused },
                set: { environment.isPaused = $0 }
            ))

            Toggle("Pegar siempre como texto plano", isOn: Binding(
                get: { environment.alwaysPlainText },
                set: { environment.alwaysPlainText = $0 }
            ))

            Divider()

            Toggle("Sincronizar con iCloud", isOn: Binding(
                get: { environment.syncEnabled },
                set: { environment.syncEnabled = $0 }
            ))
            // Sin estado visible, una sincronización rota es indistinguible de
            // una ociosa.
            Text(environment.syncStatusText).font(.caption)

            // El menú se reconstruye cada vez que se abre, así que basta con
            // leer el permiso aquí para que la opción desaparezca sola en
            // cuanto se conceda desde Ajustes.
            if !environment.isAccessibilityTrusted {
                Divider()
                Button("Activar Direct Paste…") { environment.requestAccessibility() }
            }

            if let error = environment.openError {
                Divider()
                Text(error).font(.caption)
            }

            Divider()

            Button("Salir de Paste") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// Dependencias de larga vida de la app.
///
/// Si la base no abre se guarda el error en vez de reventar: una app de
/// portapapeles que no arranca es peor que una que arranca diciendo qué le pasa.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var store: ClipboardStore?
    private(set) var watcher: PasteboardWatcher?
    private(set) var writer: ClipboardWriter?
    private(set) var openError: String?

    let icons = AppIconCache()
    let panel = PanelController()

    private let settingsStore = CaptureSettingsStore()
    private let pasteSettings = PasteSettingsStore()
    private var sync: CloudSyncEngine?
    private let paster = DirectPaster()
    private let hotKeys = HotKeyCenter()
    private var retentionTimer: Timer?

    /// Historial conservado por defecto. Los elementos de un pinboard no caducan.
    private static let retentionMaxAge: TimeInterval = 30 * 24 * 3600
    private static let retentionMaxItems = 10_000

    var isPaused: Bool {
        get { watcher?.settings.isPaused ?? false }
        set {
            guard let watcher else { return }
            watcher.settings.isPaused = newValue
            settingsStore.save(watcher.settings)
        }
    }

    var alwaysPlainText: Bool {
        get { pasteSettings.alwaysPlainText }
        set { pasteSettings.alwaysPlainText = newValue }
    }

    private(set) var syncStatusText = "Sincronización detenida"

    var syncEnabled: Bool {
        get { pasteSettings.syncEnabled }
        set {
            pasteSettings.syncEnabled = newValue
            if newValue { startSync() } else { stopSync() }
        }
    }

    /// No se guarda en una propiedad: el permiso se concede y se retira desde
    /// Ajustes sin avisar a la app.
    var isAccessibilityTrusted: Bool { AccessibilityAuthorization.isTrusted }

    func requestAccessibility() {
        // La alerta del sistema solo aparece la primera vez; después hay que
        // llevar al usuario al panel a mano o se queda sin camino.
        if !AccessibilityAuthorization.request() {
            AccessibilityAuthorization.openSettings()
        }
    }

    /// Usa un elemento: lo deja en el portapapeles, cierra el panel y lo pega en
    /// la app de destino.
    ///
    /// Si no hay permiso de Accesibilidad el pegado no ocurre y el contenido se
    /// queda en el portapapeles para pegarlo a mano (§17).
    func use(_ item: ClipboardItem, asPlainText forcePlainText: Bool = false) {
        // El destino se lee antes de esconder el panel: `hide()` no lo borra,
        // pero la siguiente apertura sí, y el pegado es asíncrono.
        let target = panel.targetApplication

        writer?.write(item, asPlainText: forcePlainText || alwaysPlainText)
        panel.hide()

        Task { await paster.paste(into: target) }
    }

    init() {
        do {
            let db = try AppDatabase.open(at: try AppPaths.databaseURL())
            let store = ClipboardStore(db)
            self.store = store

            let deviceID = settingsStore.deviceID()
            try store.registerDevice(Device(
                id: deviceID,
                name: Host.current().localizedName ?? "Mac",
                platform: .macOS
            ))

            let watcher = PasteboardWatcher(
                store: store,
                settings: settingsStore.load(),
                deviceID: deviceID
            )
            watcher.start()
            self.watcher = watcher
            self.writer = ClipboardWriter(watcher: watcher)

            configurePanel(store: store)
            startRetention(store: store)

            sync = CloudSyncEngine(store: store)
            if pasteSettings.syncEnabled { startSync() }
        } catch {
            openError = String(describing: error)
        }
    }

    private func configurePanel(store: ClipboardStore) {
        // El modelo se crea una vez y sobrevive entre aperturas: reconstruirlo
        // en cada `show` volvería a consultar la base y haría parpadear la lista.
        let model = HistoryListViewModel(store: store)
        let pinboards = PinboardListViewModel(store: store)
        panel.configure { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PanelView(environment: self, model: model, pinboards: pinboards))
        }
        hotKeys.register(.optionCommandV) { [weak self] in
            self?.panel.toggle()
        }
    }

    /// Arranca la sincronización.
    ///
    /// Un fallo aquí no puede tumbar la app: una app de portapapeles que no
    /// arranca por no tener iCloud sería absurda. Se queda en local y lo dice.
    private func startSync() {
        guard let sync else { return }
        Task {
            await sync.setStatusHandler { [weak self] status in
                Task { @MainActor in self?.syncStatusText = Self.describe(status) }
            }
            do {
                try await sync.start()
            } catch {
                syncStatusText = "iCloud no disponible"
                NSLog("Paste: no se pudo arrancar la sincronización: \(error)")
            }
        }
    }

    private func stopSync() {
        guard let sync else { return }
        Task { await sync.stop() }
    }

    private static func describe(_ status: CloudSyncEngine.Status) -> String {
        switch status {
        case .detenida: "Sincronización detenida"
        case .sincronizando: "Sincronizando…"
        case .alDia(let date):
            "Al día · \(date.formatted(date: .omitted, time: .shortened))"
        case .fallo: "Error de sincronización"
        }
    }

    /// Poda el historial al arrancar y luego cada hora.
    ///
    /// Sin esto la base crece sin límite desde el primer día. Los ajustes
    /// visibles llegan en M5; los valores por defecto se aplican ya.
    private func startRetention(store: ClipboardStore) {
        applyRetention(store: store)
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { self.applyRetention(store: store) }
        }
        timer.tolerance = 300
        retentionTimer = timer
    }

    private func applyRetention(store: ClipboardStore) {
        do {
            try store.applyRetention(
                maxAge: Self.retentionMaxAge,
                maxItems: Self.retentionMaxItems
            )
            // Las lápidas se conservan un tiempo tras el borrado para que,
            // cuando exista sincronización, el otro dispositivo se entere del
            // borrado antes de que la fila desaparezca.
            _ = try store.purgeTombstones(olderThan: Date().addingTimeInterval(-Self.retentionMaxAge))
        } catch {
            NSLog("Paste: falló la retención: \(error)")
        }
    }
}

/// Registra la app para el push silencioso.
///
/// `CKSyncEngine` gestiona su propia suscripción, pero el sistema no le entrega
/// nada si la app no se ha registrado. Sin esto la sincronización solo ocurriría
/// al arrancar y al escribir, nunca al recibir.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Sin push la app sigue sincronizando al arrancar y al escribir.
        NSLog("Paste: sin push silencioso: \(error)")
    }
}
