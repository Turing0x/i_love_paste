import AppKit
import PasteCore
import SwiftUI

@main
struct PasteMacApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            HistoryView(environment: environment)
        }
        .defaultSize(width: 560, height: 640)
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

    private let settingsStore = CaptureSettingsStore()
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

            startRetention(store: store)
        } catch {
            openError = String(describing: error)
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
