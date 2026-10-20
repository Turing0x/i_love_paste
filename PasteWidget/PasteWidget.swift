import AppIntents
import PasteCore
import SwiftUI
import WidgetKit

struct PasteEntry: TimelineEntry {
    let date: Date
    let title: String
    let items: [ClipboardItem]
    /// A dónde lleva tocar el widget.
    let url: URL
    let error: String?
    /// Sin suscripción el widget no enseña contenido, ni siquiera el que ya
    /// está guardado: es la misma pantalla de bloqueo que la app, en pequeño.
    let isLocked: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PasteEntry {
        PasteEntry(
            date: Date(),
            title: "Historial",
            items: [],
            url: URL(string: "paste://scope/history")!,
            error: nil,
            isLocked: false
        )
    }

    func snapshot(for configuration: ScopeIntent, in context: Context) async -> PasteEntry {
        entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: ScopeIntent, in context: Context) async -> Timeline<PasteEntry> {
        // La app y la extensión piden recarga al escribir, así que esta política
        // es solo la red de seguridad para cuando nadie lo haya pedido.
        Timeline(
            entries: [entry(for: configuration, family: context.family)],
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    /// Foto del historial, sin observación: un widget no está vivo, se le pide
    /// una instantánea y se apaga.
    private func entry(for configuration: ScopeIntent, family: WidgetFamily) -> PasteEntry {
        let board = configuration.pinboard
        let scope: HistoryFilter.Scope = board.map { .pinboard($0.id) } ?? .history
        let title = board?.name ?? "Historial"
        let url = board.map { URL(string: "paste://scope/pinboard/\($0.id.uuidString)")! }
            ?? URL(string: "paste://scope/history")!

        // El muro se mira antes que la base: sin suscripción no se enseña ni un
        // título de elemento, y tocar el widget lleva a suscribirse en vez de a
        // una lista vacía sin explicación.
        guard decideAccess(EntitlementStore.sharedGroup().load(), policy: .local).isGranted else {
            return PasteEntry(
                date: Date(),
                title: title,
                items: [],
                url: URL(string: "paste://paywall")!,
                error: nil,
                isLocked: true
            )
        }

        do {
            let store = try WidgetStore.open()
            let items = try store.items(
                matching: HistoryFilter(scope: scope),
                limit: family == .systemSmall ? 3 : 6
            )
            return PasteEntry(
                date: Date(),
                title: title,
                items: items,
                url: url,
                error: nil,
                isLocked: false
            )
        } catch {
            return PasteEntry(
                date: Date(),
                title: title,
                items: [],
                url: url,
                error: "Sin acceso al historial",
                isLocked: false
            )
        }
    }
}

struct PasteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "dev.threedots.paste.widget",
            intent: ScopeIntent.self,
            provider: Provider()
        ) { entry in
            PasteWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Paste")
        .description("Tu historial o un pinboard, a un toque.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PasteWidgetView: View {
    let entry: PasteEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock").font(.caption2)
                    Text("Suscripción requerida").font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if let error = entry.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if entry.items.isEmpty {
                Text("Nada guardado todavía")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.kind.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        // Tocar abre la app en esta misma lista.
        .widgetURL(entry.url)
    }
}
