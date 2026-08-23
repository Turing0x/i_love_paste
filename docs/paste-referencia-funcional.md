# Documento técnico y especificación funcional
## Aplicación Paste — Gestor avanzado de portapapeles para macOS e iPhone

**Referencia analizada:** Paste — https://pasteapp.io/  
**Plataformas:** macOS, iPhone y iPad  
**Tipo de producto:** Gestor avanzado de portapapeles, biblioteca de contenido y herramienta de productividad  
**Fecha de análisis:** agosto de 2026

---

# 1. Descripción general

Paste es una aplicación de productividad cuyo núcleo funcional es convertir el portapapeles tradicional del sistema operativo en un **historial persistente, visual, searchable, organizado y sincronizado**.

El portapapeles convencional mantiene esencialmente el último elemento copiado. Paste amplía este comportamiento almacenando el contenido que el usuario copia y permitiendo posteriormente:

- Consultar el historial.
- Buscar elementos antiguos.
- Filtrar resultados.
- Previsualizar contenido.
- Editar elementos.
- Renombrar elementos.
- Reutilizar contenido.
- Organizar elementos en colecciones llamadas **Pinboards**.
- Sincronizar el contenido entre Mac, iPhone y iPad.
- Compartir Pinboards con otros usuarios.
- Pegar contenido directamente en otras aplicaciones.
- Utilizar atajos de teclado.
- Utilizar una pila temporal de contenido mediante Paste Stack.
- Utilizar Paste como fuente de contexto para herramientas de inteligencia artificial mediante MCP.

La aplicación está profundamente integrada con macOS e iOS, intentando que la gestión del portapapeles sea una extensión natural del sistema operativo y no una aplicación independiente que el usuario tenga que utilizar constantemente.

La propia documentación de Paste describe el producto como un clipboard manager que guarda texto, enlaces, imágenes y otros contenidos para poder recuperarlos posteriormente. citeturn0search2turn0search8

---

# 2. Objetivo funcional

El objetivo principal de la aplicación es resolver cinco problemas:

### 2.1 Pérdida de información

Cuando un usuario copia un segundo elemento, el primero deja de estar disponible en el portapapeles convencional.

Paste mantiene un historial para poder recuperar elementos copiados anteriormente.

### 2.2 Repetición de acciones

El usuario puede reutilizar información copiada anteriormente sin tener que volver a localizarla en la aplicación original.

### 2.3 Falta de organización

Los elementos importantes pueden almacenarse en Pinboards permanentes.

### 2.4 Falta de búsqueda

En lugar de recorrer manualmente cientos o miles de elementos, el usuario puede realizar búsquedas y utilizar filtros.

### 2.5 Trabajo multidispositivo

El usuario puede copiar información en un Mac y recuperarla posteriormente desde el iPhone, o viceversa, mediante sincronización con iCloud. citeturn0search1turn0search11

---

# 3. Plataformas

## 3.1 macOS

macOS es la plataforma principal de Paste.

La aplicación funciona en segundo plano y monitoriza el portapapeles mientras está activa, almacenando los elementos copiados.

La versión actual requiere macOS 14 o posterior. citeturn0search13

Funciones principales:

- Captura automática del portapapeles.
- Historial ilimitado.
- Ventana principal de Paste.
- Acceso desde la barra de menús.
- Atajos de teclado.
- Búsqueda.
- Filtros.
- Pinboards.
- Drag & drop.
- Paste directo a otras aplicaciones.
- Paste Stack.
- Quick Paste.
- Pegado como texto plano.
- Edición.
- Renombrado.
- Gestión de privacidad.
- Sincronización mediante iCloud.
- Integración con herramientas de IA mediante MCP.

---

# 4. iPhone

La aplicación para iPhone comparte el concepto y modelo de datos con la versión de Mac, pero debe adaptarse a las restricciones de seguridad de iOS.

La principal diferencia técnica es que iOS no permite que una aplicación lea continuamente el portapapeles mientras permanece ejecutándose en segundo plano.

Por este motivo, Paste utiliza diferentes mecanismos para capturar información:

- Apertura de la aplicación después de copiar.
- Share Extension.
- Action Extension.
- Paste Keyboard.
- Sincronización mediante iCloud. citeturn1search3turn0search7


---

# 5. Modelo funcional principal

La aplicación puede dividirse conceptualmente en los siguientes módulos:

```text
Paste
│
├── Clipboard Engine
│   ├── Capture
│   ├── History
│   ├── Content Detection
│   └── Privacy Filtering
│
├── Content Manager
│   ├── Preview
│   ├── Edit
│   ├── Rename
│   ├── Delete
│   └── Copy / Paste
│
├── Search Engine
│   ├── Full-text search
│   ├── Metadata search
│   ├── Image text recognition
│   └── Filters
│
├── Pinboards
│   ├── Create
│   ├── Organize
│   ├── Reorder
│   ├── Share
│   └── Collaborate
│
├── Sync
│   └── Private iCloud
│
├── macOS Integration
│   ├── Menu Bar
│   ├── Keyboard Shortcuts
│   ├── Direct Paste
│   ├── Paste Stack
│   └── Quick Paste
│
├── iOS Integration
│   ├── Keyboard Extension
│   ├── Share Extension
│   ├── Action Extension
│   └── Home Screen Widget
│
└── AI Integration
    └── MCP
```

---

# 6. Gestión del historial del portapapeles

## 6.1 Captura

En Mac, Paste funciona en segundo plano y registra los elementos que el usuario copia.

Puede almacenar diferentes tipos de contenido, incluyendo:

- Texto.
- Enlaces.
- Imágenes.
- Archivos.
- Código.
- Fragmentos de texto.
- Otros contenidos compatibles con el sistema de portapapeles. citeturn0search2turn0search8


---

# 7. Tipos de contenido

Cada elemento del historial puede contener información estructurada.

Conceptualmente:

```text
ClipboardItem
│
├── ID
├── Content
├── Content Type
├── Title
├── Source Application
├── Device
├── Creation Date
├── Modification Date
├── Preview
├── Metadata
└── Pinboard Reference
```

Los principales tipos de contenido son:

### Texto

Ejemplos:

- Mensajes.
- Direcciones.
- Contraseñas.
- Código.
- Notas.
- Plantillas.
- Fragmentos de texto.

### URL

Paste puede conservar enlaces y sus metadatos.

### Imagen

Permite conservar y visualizar imágenes copiadas.

### Archivo

Los elementos copiados pueden conservarse como contenido reutilizable y, en determinadas situaciones, utilizarse para arrastrar o pegar archivos en aplicaciones o páginas web.

---

# 8. Historial cronológico

El historial funciona como una lista ordenada temporalmente.

Los elementos más recientes aparecen primero.

El usuario puede:

- Abrir un elemento.
- Previsualizarlo.
- Copiarlo nuevamente.
- Editarlo.
- Renombrarlo.
- Eliminarlo.
- Añadirlo a un Pinboard.
- Buscarlo.
- Filtrarlo.

En iPhone, la pantalla principal muestra igualmente los elementos del historial en orden cronológico. citeturn0search7

---

# 9. Búsqueda

La búsqueda es uno de los componentes fundamentales de Paste.

La aplicación indexa el contenido almacenado para poder localizarlo posteriormente.

El usuario puede buscar:

- Texto.
- Títulos.
- URLs.
- Metadatos.
- Contenido asociado a aplicaciones.
- Elementos copiados desde determinados dispositivos.
- Texto contenido dentro de imágenes.

Los resultados se actualizan mientras el usuario escribe. citeturn1search0

---

# 10. OCR / búsqueda dentro de imágenes

Una funcionalidad especialmente importante es la posibilidad de encontrar texto dentro de imágenes.

Ejemplo:

El usuario copia una captura de pantalla que contiene:

```text
API_KEY=123456
```

Posteriormente puede buscar:

```text
API_KEY
```

y Paste puede localizar la imagen aunque el texto no exista como texto independiente.

Esto convierte las imágenes almacenadas en contenido searchable.

La documentación oficial indica que Paste reconoce texto dentro de imágenes y utiliza ese contenido para las búsquedas. citeturn1search0

---

# 11. Sistema de filtros

Los filtros permiten reducir los resultados de búsqueda.

Los criterios incluyen:

### Tipo

- Texto.
- Imagen.
- Enlace.
- Archivo.
- Otros tipos compatibles.

### Aplicación de origen

Ejemplo:

```text
Safari
Xcode
Telegram
Mail
Chrome
Finder
```

### Fecha

Permite localizar elementos copiados:

- Recientemente.
- En una fecha determinada.
- En períodos anteriores.

### Dispositivo

Permite identificar si el contenido fue generado desde:

- Mac.
- iPhone.
- iPad.

Los filtros pueden combinarse con la búsqueda textual. citeturn1search0

---

# 12. Jump to History

Paste dispone de una funcionalidad denominada **Jump to History**.

Cuando un resultado aparece dentro de una búsqueda, el usuario puede saltar directamente desde el resultado hasta la posición original del elemento dentro de:

- Clipboard History.
- Un Pinboard.

Esto permite recuperar el contexto del elemento dentro de la colección donde se encuentra almacenado.

Esta función fue incorporada en 2026. citeturn2search14

---

# 13. Previsualización

Paste utiliza una interfaz visual para mostrar el contenido antes de reutilizarlo.

Dependiendo del contenido, el usuario puede visualizar:

- Texto.
- Imágenes.
- Enlaces.
- Archivos.
- Código.
- Otros elementos.

El objetivo es poder identificar visualmente el contenido sin tener que pegarlo primero.

---

# 14. Edición de elementos

Paste permite modificar un elemento almacenado.

En Mac se puede acceder a la edición mediante:

```text
Command + E
```

o desde el menú contextual.

La edición permite modificar texto antes de volver a utilizarlo.

Las modificaciones pueden guardarse sobre el propio elemento.

En dispositivos compatibles con Apple Intelligence, las Writing Tools de Apple pueden estar disponibles durante la edición. citeturn1search1

---

# 15. Renombrado / etiquetado

Los elementos pueden recibir un título personalizado.

Esto resulta útil cuando el contenido original no proporciona un nombre suficientemente descriptivo.

Ejemplo:

```text
Elemento original:
https://api.example.com/v1/authentication...

Título personalizado:
API Authentication Endpoint
```

El título puede utilizarse posteriormente para identificar y buscar el elemento. citeturn1search1turn1search7


---

# 16. Pegado normal

El funcionamiento básico es:

```text
Usuario selecciona elemento
        ↓
Paste copia el contenido al clipboard
        ↓
Usuario utiliza Command + V
        ↓
Contenido insertado
```

En iPhone:

```text
Usuario selecciona elemento
        ↓
Paste coloca el contenido en el clipboard
        ↓
Usuario lo pega en la aplicación destino
```

---

# 17. Direct Paste en macOS

Una de las funciones más importantes de la versión Mac es la posibilidad de pegar directamente el elemento seleccionado en la aplicación activa.

Flujo:

```text
Paste abierto
      ↓
Usuario selecciona elemento
      ↓
Paste identifica aplicación activa
      ↓
Paste envía Command + V
      ↓
Aplicación activa recibe contenido
```

Para esta funcionalidad Paste necesita permiso de Accessibility en macOS.

Si el permiso no está disponible, la aplicación puede seguir funcionando y simplemente copiar el elemento seleccionado al clipboard convencional. citeturn1search2

---

# 18. Paste como texto plano

Paste puede eliminar el formato del contenido al pegarlo.

Dos modos:

### Global

Configurar:

```text
Always paste as Plain Text
```

### Individual

El usuario puede seleccionar un elemento y utilizar la opción:

```text
Paste as Plain Text
```

Esto resulta especialmente útil al copiar contenido desde:

- Word.
- Web.
- Mail.
- Documentos enriquecidos.
- Aplicaciones de diseño. citeturn1search8


---

# 19. Pinboards

Los **Pinboards** constituyen el sistema de organización permanente de Paste.

Un Pinboard puede entenderse como una colección temática de elementos.

Ejemplos:

```text
Trabajo
│
├── Email template
├── Firma
├── Dirección oficina
└── Links

Programación
│
├── API endpoints
├── Git commands
├── Flutter snippets
└── SQL queries

Proyecto X
│
├── URLs
├── Screenshots
├── Text snippets
└── Documents
```

A diferencia del historial temporal, los elementos guardados en Pinboards están diseñados para permanecer hasta que el usuario los elimine. citeturn1search9

---

# 20. Gestión de Pinboards

El usuario puede:

- Crear Pinboards.
- Nombrarlos.
- Asignarles color.
- Eliminar Pinboards.
- Reordenarlos.
- Añadir elementos.
- Eliminar elementos.
- Mover elementos.
- Reordenar elementos.

Los elementos pueden pasar del historial a un Pinboard. citeturn1search9


---

# 21. Organización mediante Drag & Drop

En macOS, los elementos pueden organizarse mediante drag & drop.

Ejemplo:

```text
Clipboard History
       │
       ├── Item A
       ├── Item B ──────────→ Pinboard "Proyecto"
       └── Item C
```

Dentro de los Pinboards también es posible modificar el orden de los elementos.

---

# 22. Shared Pinboards

Paste permite compartir Pinboards.

Esto convierte la aplicación en una herramienta de colaboración además de un clipboard manager.

Un Pinboard compartido puede utilizarse para:

- Equipos.
- Proyectos.
- Familias.
- Investigación.
- Materiales de referencia.
- Prompts de IA.
- Recursos de diseño.
- Código.

Los usuarios invitados pueden acceder al contenido compartido y los cambios se sincronizan. citeturn1search9turn2search14

---

# 23. Colaboración

El sistema de colaboración contempla:

- Invitación de usuarios.
- Control de acceso.
- Gestión de permisos.
- Contenido compartido.
- Sincronización de cambios.

La colaboración funciona tanto desde Mac como desde dispositivos iOS. citeturn2search14

---

# 24. Sincronización multidispositivo

Una de las funcionalidades centrales del producto es mantener sincronizados:

```text
Mac
 ↕
iCloud
 ↕
iPhone
 ↕
iPad
```

Se sincronizan principalmente:

- Clipboard History.
- Pinboards.
- Elementos guardados.
- Modificaciones.
- Organización.

Paste utiliza la cuenta privada de iCloud del usuario para mantener estos datos sincronizados. citeturn0search1turn0search11

---

# 25. Arquitectura de privacidad

Según la documentación oficial, el historial y los Pinboards se almacenan en los dispositivos del usuario y, cuando la sincronización está habilitada, se sincronizan mediante el iCloud privado del usuario.

Paste indica que estos datos no se almacenan en servidores propios de Paste ni en servidores de terceros para realizar la sincronización normal. citeturn0search8turn0search11

Conceptualmente:

```text
                ┌───────────────┐
                │     iCloud    │
                │   del usuario │
                └───────┬───────┘
                        │
             ┌──────────┴──────────┐
             ↓                     ↓
        ┌─────────┐          ┌─────────┐
        │   Mac   │          │ iPhone  │
        │  Paste  │          │  Paste  │
        └─────────┘          └─────────┘
```

---

# 26. Backup y recuperación

La información puede mantenerse mediante:

### iCloud

La sincronización mantiene una copia de los datos fuera de cada dispositivo individual.

### Time Machine

La documentación indica que un backup completo de Mac mediante Time Machine incluye los datos locales de Paste. citeturn0search11

---

# 27. Restricciones de privacidad

Paste proporciona mecanismos para evitar almacenar determinados contenidos.

Entre las opciones de privacidad aparecen mecanismos para ignorar:

- Aplicaciones específicas.
- Contenido temporal.
- Contenido confidencial.

Esto permite reducir el riesgo de que determinados contenidos sensibles terminen almacenados en el historial. citeturn2search3

---

# 28. Excluir aplicaciones

El usuario puede definir aplicaciones que Paste debe ignorar.

Ejemplo:

```text
Ignore Applications

├── 1Password
├── Keychain
└── Aplicación bancaria
```

Cuando una aplicación está excluida, el contenido copiado desde ella no se incorpora al historial.

---

# 29. Pausar la captura

Paste incorpora una función de pausa de la captura del portapapeles.

El usuario puede detener temporalmente la recopilación de elementos y reanudarla posteriormente.

Esto permite trabajar temporalmente sin almacenar determinados contenidos.

La función fue incorporada como **Advanced Pause Paste**. citeturn2search14

---

# 30. Paste Stack

Paste Stack es una herramienta temporal para recopilar varios elementos en un orden concreto.

Ejemplo:

```text
Copiar título
      ↓
Copiar párrafo
      ↓
Copiar imagen
      ↓
Copiar conclusión
      ↓
STACK
      ↓
Pegar todo en orden
```

Se activa mediante:

```text
Shift + Command + C
```

Todo lo que el usuario copie posteriormente se incorpora temporalmente al Stack.

Después puede pegar los elementos en el orden en que fueron recopilados.

Los elementos utilizados desaparecen automáticamente del Stack. citeturn2search7


---

# 31. Quick Paste

Quick Paste permite utilizar accesos rápidos numerados.

Ejemplo:

```text
Command + 1
Command + 2
Command + 3
...
Command + 9
```

Cada número corresponde a un elemento de la lista actual.

Esto permite reutilizar rápidamente snippets sin navegar visualmente por la interfaz. citeturn2search0

---

# 32. Atajos de teclado

La versión macOS está fuertemente orientada al teclado.

Entre los atajos principales aparecen:

```text
Shift + Command + V
→ Abrir Paste

Command + E
→ Editar

Command + R
→ Renombrar

Command + F
→ Buscar

Command + 1...9
→ Quick Paste

Shift + Command + C
→ Paste Stack
```

Los atajos forman parte esencial del flujo de trabajo de escritorio.

---

# 33. Integración con la barra de menús

Paste puede funcionar como una aplicación residente en macOS.

El usuario puede acceder al producto desde:

- Menú bar.
- Atajo de teclado.
- Ventana principal.

Esto permite que el usuario no tenga que abrir manualmente la aplicación desde Finder cada vez que quiera recuperar un elemento.

---

# 34. Integración con iOS

La versión iPhone utiliza mecanismos propios del ecosistema Apple.

Sus componentes principales son:

```text
Paste App
│
├── Clipboard History
├── Pinboards
├── Search
├── Filters
├── Share Extension
├── Action Extension
├── Paste Keyboard
├── Home Screen Widget
└── iCloud Sync
``` citeturn1search3


---

# 35. Share Extension

Desde cualquier aplicación compatible con el sistema Share Sheet, el usuario puede enviar contenido a Paste.

Ejemplo:

```text
Safari
   ↓
Share
   ↓
Paste
   ↓
Clipboard History
```

También puede utilizarse para guardar directamente contenido en un Pinboard.

Esto es especialmente importante porque permite superar parcialmente las restricciones de iOS sobre lectura del clipboard en segundo plano. citeturn1search3

---

# 36. Action Extension

La Action Extension permite enviar contenido directamente al sistema de almacenamiento de Paste desde otras aplicaciones.

Puede utilizarse para:

- Guardar contenido en historial.
- Guardar contenido en un Pinboard.
- Procesar información sin tener que navegar manualmente hasta Paste.

---

# 37. Paste Keyboard

Paste incluye un teclado propio para iPhone/iPad.

Su finalidad es permitir acceder al historial directamente desde un campo de texto.

Flujo:

```text
Usuario está escribiendo
        ↓
Abre selector de teclado
        ↓
Selecciona Paste Keyboard
        ↓
Consulta Clipboard History
        ↓
Selecciona elemento
        ↓
Contenido disponible para insertar
```

El teclado también permite acceder a Pinboards y reutilizar textos, enlaces e imágenes. citeturn1search3

---

# 38. Widget de iPhone

Paste proporciona widgets para la pantalla de inicio.

Existen tamaños:

- Small.
- Medium.

El usuario puede configurar qué lista quiere mostrar:

```text
Clipboard History
```

o:

```text
Pinboard
```

Al tocar el widget, se abre directamente la lista correspondiente dentro de Paste. citeturn1search3

---

# 39. Particularidad técnica de iOS

Esta es una diferencia fundamental si se pretende desarrollar una aplicación equivalente.

En macOS:

```text
Usuario copia
      ↓
Paste está en background
      ↓
Captura automáticamente
```

En iPhone:

```text
Usuario copia
      ↓
iOS no permite captura silenciosa permanente
      ↓
Se necesita:
    ├── Abrir Paste
    ├── Share Extension
    ├── Action Extension
    └── Paste Keyboard
```

Por tanto, **no se debe diseñar la versión iOS suponiendo que puede funcionar exactamente igual que el agente de clipboard de macOS**. La arquitectura debe adaptarse a las restricciones de privacidad y ejecución de iOS. citeturn0search7turn1search3

---

# 40. Sincronización Mac ↔ iPhone

El flujo típico es:

```text
Mac
 │
 │ Usuario copia contenido
 ↓
Paste captura
 │
 ↓
Persistencia local
 │
 ↓
iCloud
 │
 ↓
iPhone
 │
 ↓
Paste History
```

Y también en sentido inverso:

```text
iPhone
 │
 │ Share Extension / Keyboard / Paste
 ↓
Persistencia
 │
 ↓
iCloud
 │
 ↓
Mac
```

---

# 41. Modelo de datos conceptual

Una implementación equivalente podría utilizar un modelo similar a:

```text
ClipboardItem
-------------------------
id
title
content
contentType
sourceApplication
sourceDevice
createdAt
updatedAt
preview
metadata
isPinned
pinboardId
```

### Pinboard

```text
Pinboard
-------------------------
id
name
color
createdAt
updatedAt
sortOrder
owner
permissions
```

### Shared Pinboard

```text
SharedPinboard
-------------------------
pinboardId
ownerId
members
permissions
createdAt
updatedAt
```

### Device

```text
Device
-------------------------
id
name
platform
osVersion
lastSync
```

---

# 42. Relaciones principales

Conceptualmente:

```text
User
 │
 ├── Devices
 │
 ├── Clipboard Items
 │
 └── Pinboards
        │
        └── Clipboard Items
```

En colaboración:

```text
User A
   │
   └──── Shared Pinboard
              │
              ├── Item 1
              ├── Item 2
              └── Item 3
              │
              └──── User B
```

---

# 43. Motor de indexación

Una aplicación equivalente necesitaría un sistema de indexación capaz de buscar rápidamente grandes cantidades de contenido.

Debería indexar:

```text
Contenido
Título
URL
Aplicación origen
Fecha
Dispositivo
Tipo
Texto extraído de imágenes
Metadatos
```

Esto permitiría consultas como:

```text
"flutter"
```

combinadas con:

```text
Type = Code
Application = Xcode
Date = Last 30 days
```

---

# 44. OCR

Para imágenes, el sistema debería implementar reconocimiento de texto.

En el ecosistema Apple, una implementación equivalente podría utilizar frameworks nativos de reconocimiento de texto para obtener:

```text
Image
 ↓
OCR
 ↓
Extracted Text
 ↓
Search Index
```

De esta manera, una captura de pantalla se convierte en contenido searchable.

---

# 45. Arquitectura recomendada para una aplicación equivalente

Si se quisiera desarrollar una aplicación con las mismas capacidades exclusivamente para Apple, una arquitectura razonable sería:

```text
                    ┌────────────────────┐
                    │      iCloud        │
                    │ CloudKit / Sync    │
                    └─────────┬──────────┘
                              │
               ┌──────────────┴──────────────┐
               │                             │
        ┌──────▼──────┐               ┌──────▼──────┐
        │    macOS    │               │    iOS      │
        │     App     │               │     App     │
        └──────┬──────┘               └──────┬──────┘
               │                             │
        ┌──────▼──────┐               ┌──────▼──────┐
        │ Clipboard   │               │ Extensions  │
        │ Monitor     │               │ Keyboard    │
        └──────┬──────┘               │ Share       │
               │                      │ Action      │
               │                      └──────┬──────┘
               │                             │
        ┌──────▼─────────────────────────────▼──────┐
        │             Shared Data Model             │
        ├───────────────────────────────────────────┤
        │ Clipboard Items                            │
        │ Pinboards                                  │
        │ Search Index                               │
        │ Metadata                                   │
        └───────────────────────────────────────────┘
```

---

# 46. Persistencia local

La aplicación debería mantener una base de datos local en cada dispositivo.

Una posible estructura:

```text
Local Database
│
├── clipboard_items
├── pinboards
├── pinboard_items
├── devices
├── metadata
├── search_index
└── settings
```

El objetivo sería permitir que la aplicación funcione rápidamente incluso sin conexión.

---

# 47. Sincronización

La sincronización debería utilizar un modelo:

```text
Local First
+
Cloud Sync
```

Es decir:

1. El usuario realiza una acción.
2. La modificación se guarda localmente.
3. La interfaz se actualiza inmediatamente.
4. La modificación se sincroniza con iCloud.
5. Los otros dispositivos reciben el cambio.
6. Se resuelven posibles conflictos.

Esto proporciona una experiencia más rápida que depender continuamente de una conexión remota.

---

# 48. Conflictos de sincronización

Un sistema equivalente debería contemplar:

```text
Mac modifica Item A
        ↓
iPhone modifica Item A
        ↓
Sync
        ↓
Conflict Resolution
```

La resolución podría basarse en:

- Timestamp.
- Versionado.
- Última modificación.
- Merge de campos.
- Identificador de operación.

---

# 49. Compartición

Los Pinboards compartidos requieren una capa adicional de sincronización.

A diferencia del historial privado:

```text
Usuario
   ↓
Private Clipboard
   ↓
iCloud personal
```

un Pinboard compartido necesita:

```text
User A
   ↓
Shared Pinboard
   ↓
Shared Cloud Data
   ↓
User B
```

Por tanto, la colaboración tiene requisitos adicionales de:

- Identidad.
- Permisos.
- Invitaciones.
- Sincronización.
- Resolución de conflictos.
- Gestión de miembros.

---

# 50. Seguridad

La seguridad debe ser considerada una parte crítica del sistema porque el clipboard puede contener información extremadamente sensible.

Posibles contenidos:

- Contraseñas.
- Tokens.
- API keys.
- Datos bancarios.
- Información personal.
- Documentos.
- Código privado.

Paste incorpora controles para evitar capturar determinados contenidos y permite excluir aplicaciones. citeturn2search3

Una aplicación equivalente debería implementar como mínimo:

```text
Application Exclusion
Sensitive Content Detection
Pause Capture
Local Encryption
Secure Cloud Sync
Access Control
```

---

# 51. Integración con inteligencia artificial

Una de las funcionalidades más recientes de Paste es **Paste MCP**.

MCP significa:

**Model Context Protocol**

Paste incorpora un servidor MCP local que permite conectar el historial del portapapeles con herramientas de IA compatibles. citeturn2search1turn2search6

---

# 52. Qué permite Paste MCP

Una herramienta de IA conectada puede:

- Buscar elementos del historial.
- Recuperar contenido copiado anteriormente.
- Utilizar notas como contexto.
- Utilizar enlaces como contexto.
- Utilizar archivos.
- Utilizar screenshots.
- Consultar Pinboards.
- Guardar nuevos elementos.
- Administrar Pinboards. citeturn2search1turn2search4


---

# 53. Integraciones de IA

Paste documenta integración con herramientas como:

- Claude.
- Claude Code.
- Codex.
- Cursor.
- VS Code.
- Windsurf.
- Herramientas MCP personalizadas. citeturn2search2turn2search12


---

# 54. Arquitectura MCP

La arquitectura conceptual es:

```text
                  ┌──────────────────┐
                  │      Paste       │
                  │      macOS       │
                  └────────┬─────────┘
                           │
                    Local MCP Server
                           │
             ┌─────────────┼─────────────┐
             ↓             ↓             ↓
          Claude         Codex        Cursor
             │             │             │
             └─────────────┼─────────────┘
                           ↓
                  Clipboard Context
```

El servidor MCP se ejecuta localmente en Mac.

El usuario debe aprobar las conexiones. citeturn2search1


---

# 55. Ejemplo de flujo con IA

Usuario:

```text
"Busca en Paste las notas que copié hoy
sobre el lanzamiento."
```

La IA:

```text
       ↓
MCP
       ↓
Paste
       ↓
Search Clipboard
       ↓
Results
       ↓
AI
       ↓
Resumen / respuesta
```

Esto transforma el clipboard en una especie de **memoria contextual del flujo de trabajo del usuario**.

---

# 56. MCP y privacidad

El servidor MCP funciona localmente en Mac.

Paste no entrega automáticamente el historial a una IA.

La herramienta conectada debe solicitar el contenido mediante la conexión autorizada.

El usuario puede:

- Ver conexiones.
- Revocar acceso.
- Desactivar MCP.
- Desconectar herramientas.

La privacidad posterior del contenido dependerá también de la herramienta de IA conectada. citeturn2search1

---

# 57. Funciones de productividad

El conjunto de funcionalidades convierte Paste en algo más que un clipboard manager.

Puede utilizarse como:

### Biblioteca de snippets

```text
Code
Commands
SQL
Regex
API requests
```

### Biblioteca de contenido

```text
Emails
Templates
URLs
Notes
Addresses
```

### Biblioteca de investigación

```text
Articles
Screenshots
Links
Quotes
References
```

### Biblioteca de diseño

```text
Colors
Images
References
Copy
```

### Memoria para IA

```text
Notes
Research
Prompts
Files
Screenshots
```

---

# 58. Flujo de usuario principal

## Flujo A — Copiar y recuperar

```text
Copy
 ↓
Paste captures
 ↓
Later
 ↓
Open Paste
 ↓
Select item
 ↓
Paste
```

---

## Flujo B — Buscar

```text
Open Paste
 ↓
Search
 ↓
Type query
 ↓
Filters
 ↓
Select result
 ↓
Paste
```

---

## Flujo C — Guardar permanentemente

```text
Copy
 ↓
Clipboard History
 ↓
Pin
 ↓
Pinboard
 ↓
Permanent reusable item
```

---

## Flujo D — Mac → iPhone

```text
Copy on Mac
 ↓
Paste
 ↓
iCloud
 ↓
iPhone
 ↓
Paste Keyboard / App
 ↓
Reuse
```

---

## Flujo E — iPhone → Mac

```text
Copy / Share on iPhone
 ↓
Paste
 ↓
iCloud
 ↓
Mac
 ↓
Clipboard History
 ↓
Reuse
```

---

# 59. Diferencias funcionales Mac vs iPhone

| Funcionalidad | macOS | iPhone |
|---|---:|---:|
| Historial de clipboard | Sí | Sí |
| Captura automática | Sí | Limitada por iOS |
| Pinboards | Sí | Sí |
| Búsqueda | Sí | Sí |
| Filtros | Sí | Sí |
| OCR / búsqueda en imágenes | Sí | Sí |
| Edición | Sí | Sí |
| Renombrado | Sí | Sí |
| iCloud Sync | Sí | Sí |
| Direct Paste | Sí | No equivalente |
| Paste Keyboard | No necesario | Sí |
| Share Extension | No necesaria | Sí |
| Action Extension | No necesaria | Sí |
| Home Screen Widget | No | Sí |
| Paste Stack | Sí | No |
| Quick Paste | Sí | No |
| MCP | Sí | No |
| Menu Bar | Sí | No |
| Accessibility integration | Sí | No |
| Shared Pinboards | Sí | Sí |

Las diferencias se deben principalmente a las capacidades y restricciones propias de cada sistema operativo. citeturn1search3turn1search2turn2search1

---

# 60. Funcionalidades críticas

Si se quisiera construir un producto equivalente, las funcionalidades que definen realmente el producto serían:

### Nivel 1 — Core

1. Captura de clipboard.
2. Historial.
3. Persistencia.
4. Visualización.
5. Copiar nuevamente.
6. Búsqueda.
7. Pinboards.
8. Sincronización.

### Nivel 2 — Productividad

9. Atajos de teclado.
10. Quick Paste.
11. Paste Stack.
12. Direct Paste.
13. Plain Text Mode.
14. Drag & Drop.
15. Edición.
16. Renombrado.

### Nivel 3 — iOS

17. Share Extension.
18. Action Extension.
19. Paste Keyboard.
20. Widget.
21. Sincronización iCloud.

### Nivel 4 — Colaboración

22. Shared Pinboards.
23. Invitaciones.
24. Permisos.
25. Sincronización multiusuario.

### Nivel 5 — Inteligencia

26. OCR.
27. Indexación avanzada.
28. MCP.
29. Integraciones con herramientas de IA.

---

# 61. MVP recomendado

Si el objetivo fuera desarrollar una aplicación propia inspirada en Paste, no sería recomendable intentar implementar todas las funciones simultáneamente.

Un MVP podría contener:

```text
MVP
│
├── macOS
│   ├── Clipboard monitoring
│   ├── History
│   ├── Search
│   ├── Preview
│   ├── Copy back
│   └── Pinboards
│
├── iPhone
│   ├── History
│   ├── Search
│   ├── Pinboards
│   ├── Share Extension
│   └── Keyboard Extension
│
└── Sync
    └── iCloud
```

---

# 62. Segunda fase

Posteriormente:

```text
Phase 2
│
├── Direct Paste
├── Keyboard shortcuts
├── Quick Paste
├── Paste Stack
├── OCR
├── Plain Text Mode
├── Privacy exclusions
└── Widgets
```

---

# 63. Tercera fase

Finalmente:

```text
Phase 3
│
├── Shared Pinboards
├── Collaboration
├── Multi-user permissions
├── AI/MCP
├── Advanced search
└── Advanced automation
```

---

# 64. Consideraciones de implementación

Para un producto Apple-first, una implementación nativa sería la opción más adecuada.

### macOS

Tecnologías potenciales:

- Swift.
- SwiftUI.
- AppKit cuando sea necesario.
- NSPasteboard.
- Accessibility APIs.
- Menu Bar integration.
- Core Data / SwiftData.
- CloudKit.
- Vision Framework.
- Natural Language / Search indexing.
- MCP local server.

### iOS

Tecnologías potenciales:

- Swift.
- SwiftUI.
- Keyboard Extension.
- Share Extension.
- Action Extension.
- WidgetKit.
- CloudKit.
- Vision Framework.
- App Intents.

---

# 65. Consideración importante sobre Flutter

Si el objetivo es crear una aplicación similar a Paste, Flutter puede utilizarse para la interfaz compartida, pero **no debería considerarse suficiente por sí solo para el núcleo funcional**.

El producto depende fuertemente de APIs específicas de Apple:

```text
macOS Clipboard
Accessibility
Menu Bar
Background execution
iOS Keyboard Extension
Share Extension
Action Extension
WidgetKit
CloudKit
App Intents
MCP
```

Por ello, una arquitectura Flutter razonable sería:

```text
Flutter
   │
   ├── UI compartida
   │
   └── Native Apple Modules
          │
          ├── macOS Clipboard
          ├── macOS Accessibility
          ├── iOS Keyboard
          ├── iOS Share Extension
          ├── Widget
          ├── CloudKit
          └── MCP
```

Para conseguir una integración realmente profunda con macOS e iOS, Swift/SwiftUI + componentes nativos probablemente proporcionaría una arquitectura más limpia.

---

# 66. Resumen funcional completo

Paste puede entenderse como la combinación de:

```text
             ┌──────────────────────────┐
             │       PASTE APP          │
             └────────────┬─────────────┘
                          │
        ┌─────────────────┼──────────────────┐
        │                 │                  │
        ↓                 ↓                  ↓
   CLIPBOARD          ORGANIZATION        SEARCH
        │                 │                  │
        ├── History       ├── Pinboards      ├── Text
        ├── Capture       ├── Colors         ├── Filters
        ├── Preview       ├── Reorder        ├── Metadata
        ├── Edit          └── Sharing        └── OCR
        └── Paste
                          │
        ┌─────────────────┼──────────────────┐
        │                 │                  │
        ↓                 ↓                  ↓
       SYNC             PRODUCTIVITY        AI
        │                 │                  │
      iCloud          Shortcuts             MCP
        │             Quick Paste             │
        │             Paste Stack              │
        │             Direct Paste             │
        │             Plain Text               │
        │                                      │
        └──────────────┬───────────────────────┘
                       ↓
                 Apple Ecosystem
                       │
              ┌────────┼────────┐
              ↓        ↓        ↓
             Mac     iPhone    iPad
```

---

# 67. Conclusión

Paste no debe conceptualizarse simplemente como una aplicación que “guarda el clipboard”.

Su arquitectura funcional actual se puede resumir como:

**Clipboard Manager + Search Engine + Personal Content Library + Cross-device Sync + Collaboration + AI Context Layer.**

El núcleo sigue siendo el historial del portapapeles, pero las funcionalidades de búsqueda, Pinboards, sincronización, extensiones de iOS, colaboración y MCP convierten el producto en una plataforma mucho más completa.

Las capacidades especialmente diferenciadoras son:

1. **Historial persistente del clipboard.**
2. **Búsqueda de todo lo copiado.**
3. **Filtros por contenido, aplicación, fecha y dispositivo.**
4. **OCR y búsqueda dentro de imágenes.**
5. **Pinboards permanentes.**
6. **Sincronización Mac/iPhone/iPad mediante iCloud.**
7. **Paste directo en aplicaciones de macOS.**
8. **Paste Stack para recopilar múltiples elementos.**
9. **Quick Paste mediante atajos.**
10. **Paste Keyboard para iPhone.**
11. **Share/Action Extensions para iOS.**
12. **Widgets de iPhone.**
13. **Controles de privacidad y exclusión de aplicaciones.**
14. **Pinboards compartidos y colaboración.**
15. **Integración con IA mediante MCP.**

La documentación oficial confirma además que Paste continúa incorporando funcionalidades nuevas: MCP en junio de 2026, Jump to History en abril de 2026 y previamente Shared Pinboards, entre otras mejoras. citeturn2search14

Por tanto, si el propósito de este documento es **utilizar Paste como referencia para desarrollar una aplicación propia**, el producto debería dividirse técnicamente en tres grandes capas:

```text
1. CORE CLIPBOARD
   Captura + almacenamiento + búsqueda + reutilización

2. APPLE INTEGRATION
   macOS + iOS + Extensions + Keyboard + iCloud

3. PRODUCTIVITY / AI
   Pinboards + Collaboration + OCR + MCP
```

Esta separación permite desarrollar primero el núcleo y posteriormente añadir las funciones avanzadas sin tener que rediseñar toda la arquitectura.