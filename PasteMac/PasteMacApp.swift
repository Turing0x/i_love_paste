import PasteCore
import SwiftUI

@main
struct PasteMacApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            HistoryDebugView(environment: environment)
        }
    }
}

/// Dependencias de larga vida de la app.
///
/// La base se abre una sola vez al arrancar; si falla, se guarda el error en vez
/// de reventar, porque una app de portapapeles que no arranca es peor que una
/// que arranca diciendo qué le pasa.
@Observable
final class AppEnvironment {
    private(set) var store: ClipboardStore?
    private(set) var openError: String?

    init() {
        do {
            let db = try AppDatabase.open(at: try AppPaths.databaseURL())
            store = ClipboardStore(db)
        } catch {
            openError = String(describing: error)
        }
    }
}

/// Ventana provisional del hito M0: solo comprueba que la base abre, migra y
/// consulta. La sustituye el panel real en M2.
struct HistoryDebugView: View {
    let environment: AppEnvironment
    @State private var items: [ClipboardItem] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste — M0")
                .font(.headline)

            if let error = environment.openError ?? loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if items.isEmpty {
                Text("Base de datos abierta y migrada. Historial vacío: el capturador llega en M1.")
                    .foregroundStyle(.secondary)
            } else {
                List(items) { item in
                    VStack(alignment: .leading) {
                        Text(item.displayTitle).lineLimit(1)
                        Text(item.sourceAppName ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
        .task {
            guard let store = environment.store else { return }
            do {
                items = try store.items(limit: 100)
            } catch {
                loadError = String(describing: error)
            }
        }
    }
}
