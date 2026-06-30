import AppKit

/// A user-configurable global hotkey. Three flavors are supported:
/// - the **Fn** key (`keyCode == Hotkey.fnKeyCode`)
/// - a **modifier key on its own** (e.g. Right ⌘) — detected via `isModifierKey`
/// - a **regular key**, optionally combined with modifiers (e.g. ⌥Space)
struct Hotkey: Codable, Equatable {
    static let fnKeyCode = -1

    /// CGKeyCode of the trigger key, or `fnKeyCode` for the Fn key.
    var keyCode: Int
    /// Required modifier mask (raw `CGEventFlags`, device-independent bits only).
    /// Ignored when the hotkey is the Fn key or a bare modifier key.
    var modifiers: UInt64

    var isFn: Bool { keyCode == Hotkey.fnKeyCode }
    var isModifierKey: Bool { Hotkey.modifierFlag(forKeyCode: keyCode) != nil }

    static let fn = Hotkey(keyCode: fnKeyCode, modifiers: 0)

    // MARK: - Codable via UserDefaults

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    static func decode(_ data: Data?) -> Hotkey? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    // MARK: - Modifier key map

    /// Maps a modifier key's keycode to its device-independent `CGEventFlags` mask.
    static func modifierFlag(forKeyCode code: Int) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand    // R⌘, L⌘
        case 56, 60: return .maskShift      // L⇧, R⇧
        case 58, 61: return .maskAlternate  // L⌥, R⌥
        case 59, 62: return .maskControl    // L⌃, R⌃
        default: return nil
        }
    }

    // MARK: - Display

    /// Human-readable form, e.g. "fn", "⌘", "⌥Space".
    var displayString: String {
        if isFn { return "fn" }
        if isModifierKey { return Hotkey.keyName(forKeyCode: keyCode) }
        var s = ""
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        s += Hotkey.keyName(forKeyCode: keyCode)
        return s.isEmpty ? "—" : s
    }

    static func keyName(forKeyCode code: Int) -> String {
        if let modName = modifierKeyNames[code] { return modName }
        if let name = keyNames[code] { return name }
        return "Key\(code)"
    }

    private static let modifierKeyNames: [Int: String] = [
        54: "Right ⌘", 55: "⌘",
        56: "⇧", 60: "Right ⇧",
        58: "⌥", 61: "Right ⌥",
        59: "⌃", 62: "Right ⌃",
    ]

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
