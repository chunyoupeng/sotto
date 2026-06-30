import AppKit

/// Injects text directly into the focused app by synthesizing Unicode keyboard
/// events (like an IME committing text), rather than going through the
/// clipboard. This keeps the user's clipboard untouched and avoids the
/// IME-switching dance that Cmd+V pasting requires.
final class TextInjector {
    /// Max UTF-16 code units per synthesized event. Kept small for reliability
    /// across apps; CGEvent's unicode string has practical length limits.
    private let chunkSize = 20

    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let src = CGEventSource(stateID: .privateState)
        let units = Array(text.utf16)

        var i = 0
        while i < units.count {
            let end = min(i + chunkSize, units.count)
            let chunk = Array(units[i..<end])
            i = end

            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { continue }

            chunk.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            }

            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)

            // Small gap so fast-redrawing apps keep up with the synthetic input.
            usleep(1_500)
        }
    }
}
