import PasteCore
import SwiftUI
import UIKit
import WidgetKit

@main
struct PasteiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .onOpenURL { environment.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // En iOS el push silencioso llega cuando el sistema quiere. Abrir la
            // app es justo cuando el usuario espera ver lo que copió en el Mac,
            // así que volver a primer plano fuerza una sincronización.
            if phase == .active { environment.syncNow() }
        }
    }
}

/// Dependencias de larga vida de la app.
///
/// Gemelo del `AppEnvironment` del Mac, con la misma política de fallo: si la
/// base no abre se guarda el error en vez de reventar.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var store: ClipboardStore?
    private(set) var capture: SharedCapture?
    private(set) var openError: String?

    /// Los modelos viven aquí y no dentro de la vista para que algo de fuera
    /// —tocar el widget— pueda cambiar el ámbito con la app ya abierta.
    private(set) var history: HistoryListViewModel?
    private(set) var pinboards: PinboardListViewModel?

    private var sync: CloudSyncEngine?
    private var retentionTimer: Timer?

    /// Mismos valores que en el Mac: el historial es uno solo y caducar distinto
    /// en cada dispositivo haría reaparecer elementos al sincronizar.
    private static let retentionMaxAge: TimeInterval = 30 * 24 * 3600
    private static let retentionMaxItems = 10_000

    init() {
        do {
            // `SharedCapture` abre la base en el grupo compartido, que es lo que
            // hace que la Share Extension escriba donde la app lee, y trae ya la
            // política de captura montada.
            let capture = try SharedCapture()
            let store = capture.store
            self.capture = capture
            self.store = store

            try store.registerDevice(Device(
                id: capture.deviceID,
                name: UIDevice.current.name,
                platform: .iOS
            ))

            history = HistoryListViewModel(store: store)
            pinboards = PinboardListViewModel(store: store)

            let sync = CloudSyncEngine(store: store)
            self.sync = sync
            Task { try? await sync.start() }

            startRetention(store: store)
        } catch {
            openError = String(describing: error)
        }
    }

    /// Abre la lista que pide un enlace del widget.
    ///
    /// Formas admitidas: `paste://scope/history` y
    /// `paste://scope/pinboard/<uuid>`. Un enlace que no se entienda se ignora:
    /// abrir la app en el historial es un destino razonable para cualquier cosa.
    func open(_ url: URL) {
        guard url.scheme == "paste", url.host == "scope" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }

        switch parts.first {
        case "history":
            history?.scope = .history
        case "pinboard":
            guard let id = parts.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return }
            history?.scope = .pinboard(id)
        default:
            break
        }
    }

    /// Arranca el motor si estaba parado. `start()` es idempotente.
    func syncNow() {
        guard let sync else { return }
        Task { try? await sync.start() }
        // La sincronización trae elementos nuevos del Mac, y el widget no se
        // entera solo. Es una petición, no una orden: WidgetKit decide cuándo.
        WidgetCenter.shared.reloadAllTimelines()
    }

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
            _ = try store.purgeTombstones(
                olderThan: Date().addingTimeInterval(-Self.retentionMaxAge)
            )
        } catch {
            NSLog("Paste: falló la retención: \(error)")
        }
    }
}

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        if let store = environment.store,
           let history = environment.history,
           let pinboards = environment.pinboards {
            HistoryView(
                store: store,
                capture: environment.capture,
                model: history,
                pinboards: pinboards
            )
        } else {
            ContentUnavailableView(
                "No se pudo abrir el historial",
                systemImage: "exclamationmark.triangle",
                description: Text(environment.openError ?? "")
            )
        }
    }
}

/// Registra la app para el push silencioso.
///
/// `CKSyncEngine` gestiona su propia suscripción, pero el sistema no le entrega
/// nada si la app no se ha registrado. Gemelo del `AppDelegate` del Mac, y por
/// el mismo motivo.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Sin push la app sigue sincronizando al volver a primer plano.
        NSLog("Paste: sin push silencioso: \(error)")
    }
}
