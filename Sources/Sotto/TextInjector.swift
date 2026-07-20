import AppKit

/// Injects text directly into the focused app by synthesizing Unicode keyboard
/// events (like an IME committing text), rather than going through the
/// clipboard. This keeps the user's clipboard untouched and avoids the
/// IME-switching dance that Cmd+V pasting requires.
final class TextInjector {
    /// Max UTF-16 code units per synthesized event. Kept small for reliability
    /// across apps; CGEvent's unicode string has practical length limits.
    private let chunkSize = 20

    /// Serial, so overlapping inject calls keep their text in order, and the
    /// inter-chunk sleeps never stall the main thread.
    private let queue = DispatchQueue(label: "com.chunyoupeng.Sotto.inject", qos: .userInteractive)

    func inject(_ text: String) {
        guard !text.isEmpty else { return }
        queue.async {
            if Self.requiresPaste(text) {
                self.pastePreservingClipboard(text)
            } else {
                self.postEvents(for: text)
            }
        }
    }

    /// Some controls reject a Unicode CGEvent containing line separators and
    /// fall back to its physical key code (virtual key 0 is "A"). Paste is the
    /// only cross-app path that also preserves multiline text in terminal UIs.
    static func requiresPaste(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .newlines) != nil
    }

    private func pastePreservingClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return
        }
        let temporaryChangeCount = pasteboard.changeCount

        let src = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else {
            snapshot.restore(to: pasteboard)
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        // Let the target consume the pasteboard before restoring it. If the
        // user copied something meanwhile, keep their newer clipboard instead.
        usleep(250_000)
        if pasteboard.changeCount == temporaryChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    private func postEvents(for text: String) {
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

/// A value copy of every pasteboard item and representation. Keeping all types
/// preserves rich text, images, files, and app-specific clipboard contents.
private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
