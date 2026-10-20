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
            if case .locked(let reason) = environment.access {
                lockedMenu(reason)
            } else {
                fullMenu
            }
        }
    }

    /// Bloqueado no se enseñan las preferencias: pausar la captura o elegir si se
    /// sincroniza no significan nada cuando no se está capturando nada.
    @ViewBuilder
    private func lockedMenu(_ reason: LockReason) -> some View {
        Text(MacLockedCopy.title(reason))
        Text(MacLockedCopy.detail(reason)).font(.caption)

        Divider()

        Button("Comprobar de nuevo") { environment.refreshAccess() }

        Divider()

        Button("Salir de Paste") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var fullMenu: some View {
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

        // El estado se lee del sistema en cada apertura del menú, no de una
        // preferencia propia: el usuario puede desactivarlo desde Ajustes >
        // Elementos de inicio y la app no se entera.
        Toggle("Abrir al iniciar sesión", isOn: Binding(
            get: { environment.opensAtLogin },
            set: { environment.opensAtLogin = $0 }
        ))

        Divider()

        Toggle("Sincronizar con iCloud", isOn: Binding(
            get: { environment.syncEnabled },
            set: { environment.syncEnabled = $0 }
        ))
        // Sin estado visible, una sincronización rota es indistinguible de
        // una ociosa.
        Text(environment.syncStatusText).font(.caption)

        // El push silencioso llega cuando el sistema quiere. Esto es el
        // camino para cuando el usuario ya está mirando y no quiere esperar.
        Button("Sincronizar ahora") { environment.syncNow() }
            .disabled(!environment.syncEnabled)

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

    // El dominio de preferencias se pasa explícito: la instancia de depuración
    // usa el suyo para no compartir `deviceID` con la principal.
    private let settingsStore = CaptureSettingsStore(defaults: .pasteInstance)
    private let pasteSettings = PasteSettingsStore()
    // Mismo dominio que `settingsStore`: la instancia de depuración no debe
    // compartir "última posición" con la principal.
    private let lastScope = LastScopeStore(defaults: .pasteInstance)

    /// El Mac no vende nada: lee la copia del derecho que publica el iPhone. Una
    /// compilación con Developer ID no tiene recibo, así que StoreKit aquí no
    /// responde nada útil.
    private let entitlements = EntitlementStore(defaults: .pasteInstance)
    private(set) var access: AccessDecision = .locked(.mirrorNeverSeen)
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

    var opensAtLogin: Bool {
        get { LoginItem.isEnabled }
        set { LoginItem.setEnabled(newValue) }
    }

    private(set) var syncStatusText = "Sincronización detenida"

    var syncEnabled: Bool {
        get { pasteSettings.syncEnabled }
        set {
            pasteSettings.syncEnabled = newValue
            if newValue { startSync() } else { stopSync() }
        }
    }

    /// Por qué se descartó lo último que se copió, o `nil` si no hay nada que
    /// contar.
    ///
    /// El vigilante ya lo apuntaba; lo que faltaba era enseñarlo. `unchanged` y
    /// `empty` no son descartes que explicar —no había nada que guardar—, y su
    /// explicación es la cadena vacía.
    var lastSkipExplanation: String? {
        guard let reason = watcher?.lastSkip else { return nil }
        let text = reason.explanation
        return text.isEmpty ? nil : text
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
        access = decideAccess(entitlements.load(), policy: .mirror)

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
            // Bloqueado no se captura: seguir llenando un historial que el
            // usuario no puede abrir es quedarse con lo que copia a cambio de
            // nada.
            if access.isGranted { watcher.start() }
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

        // Se carga una sola vez al arrancar; el guardado sigue enganchado
        // mientras el modelo viva, que es toda la sesión de la app.
        model.scope = lastScope.load()
        model.onScopeChange = { [lastScope] scope in lastScope.save(scope) }

        panel.configure { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            if case .locked(let reason) = access {
                return AnyView(MacLockedView(reason: reason) { [weak self] in
                    self?.refreshAccess()
                })
            }
            return AnyView(PanelView(environment: self, model: model, pinboards: pinboards))
        }
        hotKeys.register(.optionCommandV) { [weak self] in
            self?.panel.toggle()
        }
    }

    /// Vuelve a decidir el acceso con lo que haya en la caché del espejo.
    ///
    /// El capturador se arranca o se para aquí y no en la vista: es lo único que
    /// sigue tocando datos del usuario con la app bloqueada.
    func refreshAccess() {
        let previous = access.isGranted
        access = decideAccess(entitlements.load(), policy: .mirror)
        guard access.isGranted != previous else { return }

        if access.isGranted {
            watcher?.start()
        } else {
            watcher?.stop()
            panel.hide()
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

    /// Fuerza un ciclo de sincronización.
    ///
    /// Lo llama el menú y también la apertura del panel: abrirlo es justo cuando
    /// el usuario espera ver lo que copió en el iPhone. La apertura no lo fuerza
    /// —el panel se abre muchas veces al día— y el botón sí.
    func syncNow(force: Bool = true) {
        guard let sync, syncEnabled else { return }
        Task { await sync.syncNow(force: force) }
    }

    private static func describe(_ status: CloudSyncEngine.Status) -> String {
        switch status {
        case .detenida: "Sincronización detenida"
        case .sincronizando: "Sincronizando…"
        case .alDia(let date):
            "Al día · \(date.formatted(date: .omitted, time: .shortened))"
        // El motivo se enseña recortado: "Error de sincronización" a secas no
        // deja nada que hacer al que lo lee.
        case .fallo(let reason): "Error de sincronización · \(reason.prefix(80))"
        }
    }

    /// Poda el historial al arrancar y luego cada hora.
    ///
    /// Sin esto la base crece sin límite desde el primer día. Los ajustes
    /// visibles llegan en M5; los valores por defecto se aplican ya.
    private func startRetention(store: ClipboardStore) {
        applyRetention(store: store)
        // `[weak self]`: el temporizador retiene su cierre, el cierre retendría
        // al entorno y el entorno retiene al temporizador. El ciclo no se nota
        // en un objeto que vive lo que la app, pero el vigilante del
        // portapapeles ya lo evita y tener dos patrones distintos para lo mismo
        // acaba con alguien copiando el equivocado.
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyRetention(store: store) }
        }
        timer.tolerance = 300
        retentionTimer = timer
    }

    /// Lanza la poda sin esperarla.
    ///
    /// La escritura ocurre dentro de `ClipboardStore`, fuera del actor
    /// principal: recorre el historial entero y hacerlo aquí congelaba el
    /// pintado una vez por hora, y otra en el arranque.
    private func applyRetention(store: ClipboardStore) {
        Task {
            do {
                try await store.applyRetention(
                    maxAge: Self.retentionMaxAge,
                    maxItems: Self.retentionMaxItems
                )
                // Las lápidas se conservan un tiempo tras el borrado para que el
                // otro dispositivo se entere antes de que la fila desaparezca.
                _ = try await store.purgeTombstones(
                    olderThan: Date().addingTimeInterval(-Self.retentionMaxAge)
                )
            } catch {
                NSLog("Paste: falló la retención: \(error)")
            }
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
