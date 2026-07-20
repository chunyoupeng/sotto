import AppKit

/// A small floating editor for fixing one dictation's text. Shows the raw ASR
/// output for reference, with an editable field pre-filled with the current
/// best text. Press ↩ to save: the correction feeds local personalization and
/// is copied to the clipboard, ready to paste. Esc (or ✕) cancels.
///
/// The panel is non-activating, like the QA panel: summoning it from the
/// global hotkey must not activate Sotto or drag the main window over the
/// user's workspace — they're mid-task in another app.
final class RecordEditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let record: DictationRecord
    private let onSave: (String) -> Void
    private var textView: NSTextView!

    /// Keep a strong reference to the live editor so it is not deallocated while
    /// shown (it is created on demand and otherwise has no owner).
    private static var active: RecordEditorWindowController?

    /// Borderless non-activating panel that still takes keyboard focus, and
    /// routes ⌘-key editing shortcuts itself — with the app inactive the main
    /// menu doesn't service key equivalents, so ⌘V/⌘C/⌘Z would be dead keys.
    private final class EditorPanel: NSPanel {
        override var canBecomeKey: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let tv = firstResponder as? NSTextView {
                if mods == .command {
                    switch event.charactersIgnoringModifiers {
                    case "a": tv.selectAll(nil); return true
                    case "c": tv.copy(nil); return true
                    case "v": tv.paste(nil); return true
                    case "x": tv.cut(nil); return true
                    case "z": tv.undoManager?.undo(); return true
                    default: break
                    }
                } else if mods == [.command, .shift], event.charactersIgnoringModifiers == "z" {
                    tv.undoManager?.redo(); return true
                }
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    init(record: DictationRecord, onSave: @escaping (String) -> Void) {
        self.record = record
        self.onSave = onSave
        let win = EditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.isFloatingPanel = true
        win.level = .floating
        win.hidesOnDeactivate = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        super.init(window: win)
        win.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    static func present(for record: DictationRecord, onSave: @escaping (String) -> Void) {
        let controller = RecordEditorWindowController(record: record, onSave: onSave)
        active = controller
        if let win = controller.window, let screen = NSScreen.main {
            let area = screen.visibleFrame
            win.setFrameOrigin(NSPoint(
                x: area.midX - win.frame.width / 2,
                y: area.midY - win.frame.height / 2))
            // Key without activating: typing goes to the editor while the
            // user's app stays frontmost and regains focus on close.
            win.makeKeyAndOrderFront(nil)
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = SottoTheme.workspaceBackground.cgColor
        content.layer?.cornerRadius = 16
        content.layer?.borderWidth = 1
        content.layer?.borderColor = SottoTheme.workspaceLine.cgColor
        content.layer?.masksToBounds = true
        window?.appearance = NSAppearance(named: .darkAqua)

        let titleLabel = SottoTheme.displayLabel("修正这条记录", size: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton()
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        closeButton.isBordered = false
        closeButton.contentTintColor = SottoTheme.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(cancel)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let rawCaption = SottoTheme.captionLabel("识别原文（ASR）")

        let rawLabel = NSTextField(wrappingLabelWithString:
            record.rawText.isEmpty ? "（空）" : record.rawText)
        rawLabel.font = .systemFont(ofSize: 12)
        rawLabel.textColor = SottoTheme.secondaryLabelColor
        rawLabel.maximumNumberOfLines = 3

        let editCaption = SottoTheme.captionLabel("正确文本（保存后用于本地个性化）")

        // Editable text view inside a scroll view. Use the system factory so the
        // text container, sizing, and width-tracking are wired correctly — a bare
        // `NSTextView()` set as documentView renders empty and rejects input.
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        SottoTheme.styleAsWell(scroll, cornerRadius: 10)
        let tv = scroll.documentView as! NSTextView
        textView = tv
        tv.string = record.displayText
        tv.font = .systemFont(ofSize: 14)
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.drawsBackground = false
        tv.textColor = SottoTheme.primaryLabelColor
        tv.insertionPointColor = SottoTheme.primaryLabelColor
        tv.delegate = self

        // Bottom-right hint replaces save/cancel buttons: the whole flow is
        // keyboard-driven (↩ saves + copies, Esc backs out).
        let hint = NSTextField(labelWithString: "⌥↩ 换行 · Esc 取消 · 按回车保存并复制")
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = SottoTheme.secondaryLabelColor
        let hintRow = NSStackView(views: [NSView(), hint])
        hintRow.orientation = .horizontal

        let stack = NSStackView(views: [rawCaption, rawLabel, editCaption, scroll, hintRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(4, after: rawCaption)
        stack.setCustomSpacing(4, after: editCaption)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)
        content.addSubview(closeButton)
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
            hintRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        window?.makeFirstResponder(textView)
    }

    /// ↩ saves; ⌥↩ keeps the default line-break behavior for multi-line fixes.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            save()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        return false
    }

    @objc private func save() {
        let corrected = textView.string
        // The correction is what the user actually wanted typed — put it on the
        // clipboard so it can be pasted over the bad result immediately.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(corrected, forType: .string)
        onSave(corrected)
        NSSound(named: .init("Pop"))?.play()
        close()
    }

    @objc private func cancel() { close() }

    func windowWillClose(_ notification: Notification) {
        // Drop the static reference so the controller can deallocate.
        if RecordEditorWindowController.active === self {
            RecordEditorWindowController.active = nil
        }
    }
}
