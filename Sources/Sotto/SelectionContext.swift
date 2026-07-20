import AppKit
import ApplicationServices

/// A snapshot of the text selection that existed when a voice command began.
/// Keeping the AX element lets Sotto replace the same selection after the
/// asynchronous ASR/LLM round-trip without stealing focus from the target app.
final class SelectionSnapshot {
    let text: String
    let appName: String?
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    private let element: AXUIElement

    fileprivate init(text: String, appName: String?, bundleIdentifier: String?,
                     processIdentifier: pid_t, element: AXUIElement) {
        self.text = text
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.element = element
    }

    /// Re-check the target after ASR/LLM latency. Never write if the user has
    /// moved to another app, focused another control, or changed the selection.
    func isStillCurrent() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier == processIdentifier else { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else { return false }
        let currentElement = unsafeBitCast(focused, to: AXUIElement.self)
        guard CFEqual(currentElement, element) else { return false }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected
        ) == .success, let selectedText = selected as? String else { return false }
        return selectedText == text
    }

    /// Prefer the Accessibility write path because it performs an actual
    /// replacement and leaves the clipboard untouched. Read-only or stale
    /// selections fail closed so text is never injected into the wrong app.
    func replace(with replacement: String) -> Bool {
        guard !replacement.isEmpty, isStillCurrent() else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable
        ) == .success, settable.boolValue else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, replacement as CFString
        ) == .success
    }
}

enum SelectionCommandIntent: Equatable {
    case rewrite
    case ask
}

enum SelectionContext {
    /// Read the currently focused control and its selection. Empty selections
    /// are deliberately ignored so the QA hotkey keeps its normal popup behavior.
    static func capture() -> SelectionSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else {
            return nil
        }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected
        ) == .success, let text = selected as? String else {
            return nil
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SelectionSnapshot(
            text: text,
            appName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            element: element
        )
    }

    /// Typeless-style selection mode needs one small router: editing commands
    /// replace the selection, while questions/explanations appear in the QA panel.
    /// The LLM still receives the full command; this only chooses the destination.
    static func intent(for spokenCommand: String) -> SelectionCommandIntent {
        let command = spokenCommand.lowercased()
        let rewriteMarkers = [
            "改成", "改写", "重写", "润色", "修正", "缩短", "精简", "扩写", "变长",
            "更正式", "更专业", "更友好", "更自然", "语气", "翻译成", "整理成", "列成",
            "格式化", "回复", "生成回复", "创意回复",
            "rewrite", "rephrase", "shorten", "make it", "tone", "translate", "format", "reply",
        ]
        return rewriteMarkers.contains(where: command.contains) ? .rewrite : .ask
    }
}
