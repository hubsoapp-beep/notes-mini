import AppKit
import Carbon.HIToolbox

/// Global hotkeys through Carbon's `RegisterEventHotKey`.
///
/// Deliberately *not* NSEvent global monitors: those need Accessibility permission, Carbon hot
/// keys do not, and they work while another app is frontmost — which is the whole point of a
/// notes panel you summon from anywhere.
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private var signature: FourCharCode = 0x4E4D4B31 // 'NMK1'

    private init() {}

    /// Registers `spec` (e.g. `opt+n`, `cmd+shift+space`). Returns false when the combination
    /// is not understood or the system refused it (another app owns it).
    @discardableResult
    func register(_ spec: String, handler: @escaping () -> Void) -> Bool {
        unregister()
        guard let (keyCode, modifiers) = Self.parse(spec) else { return false }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &id)
            guard err == noErr else { return noErr }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            if id.signature == center.signature {
                center.handler?()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        guard status == noErr else { return false }

        let id = EventHotKeyID(signature: signature, id: 1)
        let regStatus = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            self.handlerRef = nil
            return false
        }
        self.handler = handler
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        handler = nil
    }

    // MARK: parsing

    struct ParseError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// `"opt+n"`, `"ctrl+alt+space"`, `"cmd+shift+k"` → Carbon key code + modifier mask.
    static func parse(_ spec: String) -> (keyCode: Int, modifiers: UInt32)? {
        let parts = spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, parts.count >= 2 else { return nil }

        var modifiers: UInt32 = 0
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            case "opt", "alt", "option", "⌥": modifiers |= UInt32(optionKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard let keyCode = keyCodes[keyPart] else { return nil }
        return (keyCode, modifiers)
    }

    /// Human-readable form for the settings UI: `⌥N`.
    static func display(_ spec: String) -> String {
        let parts = spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last else { return spec }
        var out = ""
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command": out += "⌘"
            case "ctrl", "control": out += "⌃"
            case "opt", "alt", "option": out += "⌥"
            case "shift": out += "⇧"
            default: break
            }
        }
        switch keyPart {
        case "space": out += "Space"
        case "return", "enter": out += "↩"
        case "tab": out += "⇥"
        default: out += keyPart.uppercased()
        }
        return out
    }

    /// ANSI key codes for the keys worth binding.
    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "enter": kVK_Return,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
    ]
}
