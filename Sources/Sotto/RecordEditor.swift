import AppKit
import AVFoundation

/// A small standalone editor for fixing one dictation's text. Shows the raw ASR
/// output for reference (and lets you replay the original audio), with an
/// editable field pre-filled with the current best text. Saving the corrected
/// text feeds the data flywheel — it becomes ground-truth training data.
final class RecordEditorWindowController: NSWindowController, NSWindowDelegate {
    private let record: DictationRecord
    private let onSave: (String) -> Void
    private var textView: NSTextView!
    private var player: AVAudioPlayer?

    /// Keep a strong reference to the live editor so it is not deallocated while
    /// shown (it is created on demand and otherwise has no owner).
    private static var active: RecordEditorWindowController?

    init(record: DictationRecord, onSave: @escaping (String) -> Void) {
        self.record = record
        self.onSave = onSave
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "修正这条记录"
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)
        super.init(window: win)
        win.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    static func present(for record: DictationRecord, onSave: @escaping (String) -> Void) {
        let controller = RecordEditorWindowController(record: record, onSave: onSave)
        active = controller
        controller.window?.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let rawCaption = NSTextField(labelWithString: "识别原文（ASR）")
        rawCaption.font = .systemFont(ofSize: 11)
        rawCaption.textColor = SottoTheme.secondaryLabelColor

        let rawLabel = NSTextField(wrappingLabelWithString:
            record.rawText.isEmpty ? "（空）" : record.rawText)
        rawLabel.font = .systemFont(ofSize: 12)
        rawLabel.textColor = SottoTheme.primaryLabelColor
        rawLabel.maximumNumberOfLines = 3

        let editCaption = NSTextField(labelWithString: "正确文本（保存后作为训练数据）")
        editCaption.font = .systemFont(ofSize: 11)
        editCaption.textColor = SottoTheme.secondaryLabelColor

        // Editable text view inside a scroll view. Use the system factory so the
        // text container, sizing, and width-tracking are wired correctly — a bare
        // `NSTextView()` set as documentView renders empty and rejects input.
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
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
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textColor = .textColor
        tv.insertionPointColor = .textColor

        let playButton = NSButton(title: "▶ 播放原音频", target: self, action: #selector(playAudio))
        playButton.bezelStyle = .rounded
        playButton.isHidden = RecordStore.shared.audioURL(for: record) == nil

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Esc

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Return (⌘↩ would be safer, but plain works in a button)

        let buttonRow = NSStackView(views: [playButton, NSView(), cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            rawCaption, rawLabel, editCaption, scroll, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        window?.makeFirstResponder(textView)
    }

    @objc private func playAudio() {
        guard let url = RecordStore.shared.audioURL(for: record) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    @objc private func save() {
        onSave(textView.string)
        close()
    }

    @objc private func cancel() { close() }

    func windowWillClose(_ notification: Notification) {
        player?.stop()
        // Drop the static reference so the controller can deallocate.
        if RecordEditorWindowController.active === self {
            RecordEditorWindowController.active = nil
        }
    }
}
