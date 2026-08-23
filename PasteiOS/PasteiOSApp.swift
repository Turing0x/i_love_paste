import PasteCore
import SwiftUI

@main
struct PasteiOSApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

/// La app de iPhone es fase 2. Existe ya como target para que `PasteCore`
/// compile contra iOS desde el principio: descubrir en la fase 2 que el modelo
/// compartido usa algo exclusivo de macOS sería caro.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Paste").font(.largeTitle.bold())
            Text("La app de iPhone llega en la fase 2.")
                .foregroundStyle(.secondary)
        }
    }
}
