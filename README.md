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
- **La política de captura vive en `PasteCore`, no en la app**: `CaptureEngine`
  recibe una `PasteboardSnapshot` ya extraída, así que se prueba entera sin
  portapapeles real y la reutilizará la app de iPhone.
- **La app no tiene ventanas** (`LSUIElement`): vive en la barra de menús. Es lo
  que permite que el panel flotante reciba teclado sin robarle el foco a la app
  que tengas delante, requisito del Direct Paste.
- **El atajo es ⌥⌘V, no ⇧⌘V**: registrar un atajo global se lo quita a todas las
  apps, y ⇧⌘V es "Pegar y adaptar estilo" en macOS.

## Estado

- [x] **M0** — Estructura, esquema GRDB + FTS5, tests
- [x] **M1** — Capturador de `NSPasteboard`, dedup, exclusiones, pausa, copiar al pulsar
- [x] **M2** — Panel flotante ⌥⌘V, búsqueda en vivo, filtros, Quick Paste ⌘1–9
- [ ] **M2b** — Imágenes y ficheros (aplazado)
- [x] **M3** — Direct Paste (Accesibilidad), pegar como texto plano
- [x] **M4** — Pinboards: barra lateral, colores, drag & drop
- [ ] **M5** — Ajustes, retención, edición
