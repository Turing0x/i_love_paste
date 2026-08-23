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
- **La sincronización sube desde una cola que llenan triggers SQL**, no desde el
  código Swift: es el mismo argumento que el índice FTS5: así ningún camino de
  escritura puede olvidarse de encolar.
- **`clipboardItem` no tiene clave ajena contra `pinboard`** desde la migración
  `v2.sync`. Al sincronizar, un elemento puede llegar antes que el pinboard al
  que pertenece, porque el servidor entrega los cambios por lotes.
- **La app de iPhone y su extensión comparten base** a través del App Group
  `group.dev.threedots.paste`. El Mac no lo usa: no tiene extensiones, y moverle
  la base dejaría huérfano su historial. Si el grupo no está disponible,
  `AppPaths` falla en vez de caer al contenedor propio — el fallback silencioso
  daría dos historiales que nadie ve.
- **En iOS no hay captura en segundo plano** (§39). El contenido entra por el
  botón de pegar del sistema y por la Share Extension, y las dos puertas pasan
  por `SharedCapture`, así que comparten política con el capturador del Mac.
- **La Share Extension no sincroniza**: escribe en local y la app sube lo
  encolado al abrirse.

- **Para probar la sincronización con un solo Mac**, `PASTE_DB_PATH` mueve la
  base y las preferencias de una instancia, de modo que dos copias de la app se
  comportan como dos dispositivos distintos. Solo en compilaciones de depuración.

- **El atajo es ⌥⌘V, no ⇧⌘V**: registrar un atajo global se lo quita a todas las
  apps, y ⇧⌘V es "Pegar y adaptar estilo" en macOS.

## Estado

Mac y iPhone funcionan y comparten historial por iCloud. Lo que queda del
documento de referencia son las piezas accesorias de iOS.

- [x] **M0** — Estructura, esquema GRDB + FTS5, tests
- [x] **M1** — Capturador de `NSPasteboard`, dedup, exclusiones, pausa, copiar al pulsar
- [x] **M2** — Panel flotante ⌥⌘V, búsqueda en vivo, filtros, Quick Paste ⌘1–9
- [x] **M3** — Direct Paste (Accesibilidad), pegar como texto plano
- [x] **M4** — Pinboards: barra lateral, colores, drag & drop
- [x] **M6** — Sincronización por CloudKit (`CKSyncEngine`, base privada, campos cifrados)
- [x] **M7** — App de iPhone y Share Extension
- [ ] **M8** — Teclado y widget de iPhone

### Aplazado

- **M2b — Imágenes y ficheros.** El modelo (`ContentKind.image`, `.file`) y
  `BlobStore` están listos; falta leer los tipos del pasteboard y enseñarlos.
- **M5 — Ajustes, retención y edición.** La retención ya se aplica sola con
  valores por defecto (30 días, 10 000 elementos) y respeta los pinboards, y el
  store ya sabe editar y renombrar: lo que falta es solo interfaz. Se aplaza a
  después de la sincronización a propósito, para diseñar la ventana de ajustes
  una sola vez, cuando existan también los ajustes de iCloud y de dispositivos.
  Es además la primera ventana de verdad de una app `LSUIElement`, y conviene
  resolver ese conflicto con el panel flotante una vez y no dos.
