import AppKit
import Carbon.HIToolbox

/// Atajo de teclado global.
///
/// Se usa la API Carbon `RegisterEventHotKey` porque es la única que sirve:
/// `NSEvent.addGlobalMonitorForEvents` exige permiso de Accesibilidad y, peor
/// aún, no puede consumir el evento, así que la pulsación llegaría también a la
/// app que esté debajo.
@MainActor
final class HotKeyCenter {
    /// Combinación de teclas, en constantes de Carbon.
    struct Shortcut {
        var keyCode: UInt32
        var modifiers: UInt32

        /// ⌥⌘V. No se usa ⇧⌘V, que es el atajo de Paste, porque registrarlo
        /// global se lo quitaría a todas las apps del sistema, donde significa
        /// "Pegar y adaptar estilo".
        static let optionCommandV = Shortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(optionKey | cmdKey)
        )
    }

    /// Acciones por identificador de atajo.
    ///
    /// La retrollamada de Carbon es una función C y no puede capturar contexto,
    /// así que el enlace entre el evento y lo que hay que ejecutar tiene que
    /// pasar por aquí.
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var id: UInt32?

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        unregister()

        let id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        self.id = id

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50535445), id: id) // 'PSTE'
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let id {
            Self.actions[id] = nil
            self.id = nil
        }
    }

    fileprivate static func fire(id: UInt32) {
        actions[id]?()
    }
}

/// Los eventos Carbon se despachan en el hilo principal, de ahí el
/// `assumeIsolated`: no hay salto de hilo que justificar, solo se le está
/// contando al compilador dónde estamos.
private let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    MainActor.assumeIsolated {
        HotKeyCenter.fire(id: hotKeyID.id)
    }
    return noErr
}
