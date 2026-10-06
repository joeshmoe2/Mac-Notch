import AppKit
import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut using Carbon's
/// `RegisterEventHotKey`, which (unlike a global NSEvent key monitor) does not
/// require Accessibility permission.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var appliedSignature: String?

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        unregister()
        self.action = action
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E484B59) /* 'NHKY' */, id: 1)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Re-reads the shortcut from preferences.
    func applyPreferences() {
        let signature = "\(Prefs.hotKeyEnabled.value)|\(Prefs.hotKeyCode.value)|\(Prefs.hotKeyModifiers.value)"
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        guard Prefs.hotKeyEnabled.value else { unregister(); return }
        register(keyCode: Prefs.hotKeyCode.value, modifiers: Prefs.hotKeyModifiers.value) {
            NotchWindowManager.shared.toggle()
        }
    }

    fileprivate func fire() { action?() }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyService.shared.fire() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// Helpers to convert between AppKit key events and Carbon hot key values,
/// and to display shortcuts.
enum HotKeyFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return result
    }

    static func string(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    static func keyName(_ keyCode: Int) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[keyCode] { return name }
        return characterForKeyCode(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Uses the current keyboard layout to translate a key code into a character.
    private static func characterForKeyCode(_ keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(ptr, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
