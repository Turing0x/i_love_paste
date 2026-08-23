import PasteCore
import SwiftUI
import WidgetKit

/// Qué se va a guardar y dónde.
struct ShareView: View {
    let providers: [NSItemProvider]
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var capture: SharedCapture?
    @State private var pinboards: [Pinboard] = []
    @State private var snapshot: PasteboardSnapshot?
    @State private var destination: UUID?
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Se guardará") {
                    if let text = snapshot?.string {
                        Text(text).lineLimit(4)
                    } else if error == nil {
                        // Cargar del proveedor es asíncrono y puede tardar lo
                        // suyo con contenido grande.
                        HStack { ProgressView(); Text("Leyendo…") }
                    }
                }

                // §35: la extensión sirve también para guardar directamente en
                // un pinboard, no solo en el historial.
                Section("Destino") {
                    Picker("Destino", selection: $destination) {
                        Text("Historial").tag(UUID?.none)
                        ForEach(pinboards) { board in
                            Text(board.name).tag(UUID?.some(board.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                if let error {
                    Section {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Guardar en Paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(snapshot == nil || isSaving)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            // La base se abre aquí y no en el controlador para que el error
            // tenga dónde enseñarse.
            let capture = try SharedCapture()
            self.capture = capture
            pinboards = (try? capture.store.pinboards()) ?? []
        } catch {
            self.error = error.localizedDescription
            return
        }

        snapshot = await NSItemProvider.snapshot(from: providers)
        if snapshot == nil {
            error = "No hay nada que Paste pueda guardar de esto todavía."
        }
    }

    private func save() {
        guard let capture, let snapshot else { return }
        isSaving = true
        do {
            // No se sincroniza desde aquí: los triggers dejan el elemento
            // encolado y la app lo sube al abrirse. Levantar el motor de
            // CloudKit dentro de una extensión, con su límite de memoria y su
            // plazo cortable, no compensa.
            let stored = try capture.capture(
                snapshot,
                source: SharedCapture.sharedSheet,
                pinboardID: destination
            )
            guard stored != nil else {
                error = "Paste descartó este contenido."
                isSaving = false
                return
            }
            // El widget no observa la base: hay que pedirle que se refresque.
            WidgetCenter.shared.reloadAllTimelines()
            onFinish()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
