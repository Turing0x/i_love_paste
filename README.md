# Paste

Gestor de portapapeles para macOS e iPhone. SwiftUI, sin dependencias de nube.

## Estructura

```
PasteCore/   Swift Package: modelo, base de datos (GRDB + FTS5), sync (fase 2)
PasteMac/    App de macOS
PasteiOS/    App de iPhone (fase 2)
project.yml  Fuente del .xcodeproj — el proyecto se genera, no se versiona
docs/        Referencia funcional y capturas de la app original
```

## Puesta en marcha

```sh
brew install xcodegen
xcodegen generate
open Paste.xcodeproj
```

## Tests

```sh
cd PasteCore && swift test
```

## Decisiones que conviene conocer

- **GRDB en vez de SwiftData**: SwiftData no ofrece FTS5, y sin él la búsqueda
  sobre miles de elementos es un escaneo lineal.
- **Los UUID se guardan como TEXT**, no como el BLOB de 16 bytes por omisión de
  GRDB: la base se puede inspeccionar con `sqlite3`.
- **Los borrados son lógicos** (`deletedAt`). Un borrado físico reaparecería al
  sincronizar desde el otro dispositivo.
- **La app de macOS no usa App Sandbox**: con él no hay permiso de Accesibilidad
  ni Direct Paste. Renuncia deliberada a la Mac App Store.
- **Los blobs viven en disco**, no en la base: una captura de pantalla pesa
  megabytes y lastraría cualquier consulta del historial.

## Estado

- [x] **M0** — Estructura, esquema GRDB + FTS5, tests
- [ ] **M1** — Capturador de `NSPasteboard`, dedup, exclusiones, pausa
- [ ] **M2** — Panel `NSPanel` no-activante, hotkey, búsqueda, filtros
- [ ] **M3** — Direct Paste (Accesibilidad), Quick Paste ⌘1–9
- [ ] **M4** — Pinboards
- [ ] **M5** — Ajustes, retención, edición
