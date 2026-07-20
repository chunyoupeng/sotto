import AppKit

extension Notification.Name {
    /// Posted while a hotkey is being recorded so the global key tap can pause
    /// (otherwise it would intercept Fn and fight the recorder for events).
    static let hotkeyRecordingStarted = Notification.Name("Sotto.hotkeyRecordingStarted")
    static let hotkeyRecordingStopped = Notification.Name("Sotto.hotkeyRecordingStopped")
}

/// A button that captures a global hotkey. Click it, then press the desired key
/// (Fn, a bare modifier like Right ⌘, or a key combo). Esc cancels.
final class HotkeyRecorderButton: NSButton {
    var hotkey: Hotkey? { didSet { updateTitle() } }
    var onCapture: ((Hotkey) -> Void)?
    var placeholder = "点击录入"

    private var monitor: Any?
    private var recording = false
    /// Modifier flags accumulated while modifier keys are held. Committing
    /// only on release (instead of on the first press) lets multi-modifier
    /// chords (⌃⇧, fn⇧, …) be recorded.
    private var chordMods: UInt64 = 0
    /// Keycode of the last non-Fn modifier pressed; nil means only Fn was held.
    private var chordKeyCode: Int?

    private static let relevantMods: UInt64 =
        CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue |
        Hotkey.fnModifier

    init() {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        let text = recording ? "按下快捷键…（Esc 取消）" : (hotkey?.displayString ?? placeholder)
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: recording ? SottoTheme.workspaceAccent
                                        : SottoTheme.workspacePrimaryText,
        ])
        layer?.backgroundColor = (recording
            ? SottoTheme.workspaceAccent.withAlphaComponent(0.12)
            : SottoTheme.workspaceSurface).cgColor
        layer?.borderColor = (recording
            ? SottoTheme.workspaceAccent.withAlphaComponent(0.75)
            : SottoTheme.workspaceLine).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 174, height: 32)
    }

    @objc private func beginRecording() {
        guard !recording else { return }
        recording = true
        updateTitle()
        // Pause the global key tap so Fn (and matched hotkeys) aren't swallowed
        // before we can capture them.
        NotificationCenter.default.post(name: .hotkeyRecordingStarted, object: nil)
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil  // swallow while recording
        }
    }

    private func endRecording() {
        recording = false
        chordMods = 0
        chordKeyCode = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        NotificationCenter.default.post(name: .hotkeyRecordingStopped, object: nil)
        updateTitle()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { endRecording(); return }  // Esc cancels
            let mods = UInt64(event.modifierFlags.rawValue) & HotkeyRecorderButton.relevantMods
            commit(Hotkey(keyCode: Int(event.keyCode), modifiers: mods))
            return
        }
        // flagsChanged: Fn and/or modifier keys. Accumulate while pressed and
        // commit on the first release, so chords (⌃⇧, fn⇧, …) get every key.
        let flags = event.modifierFlags
        let code = Int(event.keyCode)
        let pressed: Bool
        if code == 63 {  // the Fn key itself
            pressed = flags.contains(.function)
        } else if let modFlag = Hotkey.modifierFlag(forKeyCode: code) {
            pressed = CGEventFlags(rawValue: UInt64(flags.rawValue)).contains(modFlag)
        } else {
            return
        }
        if pressed {
            // Keep the device-specific bits (left/right identity) so chords
            // like R⌃R⌘ don't also fire for their left-hand twins.
            chordMods |= UInt64(flags.rawValue)
                & (HotkeyRecorderButton.relevantMods | Hotkey.allDeviceBits)
            if code != 63 { chordKeyCode = code }
        } else if chordMods != 0 {
            if let keyCode = chordKeyCode, let own = Hotkey.modifierFlag(forKeyCode: keyCode) {
                let ownBits = own.rawValue | (Hotkey.deviceBit(forKeyCode: keyCode) ?? 0)
                commit(Hotkey(keyCode: keyCode, modifiers: chordMods & ~ownBits))
            } else {
                commit(.fn)  // only Fn was held
            }
        }
    }

    private func commit(_ hk: Hotkey) {
        hotkey = hk
        endRecording()
        onCapture?(hk)
    }
}

/// A theme-native switch that keeps NSButton's keyboard, action and
/// accessibility behavior while replacing the stock square checkbox chrome.
final class ThemedToggleButton: NSButton {
    private var hovering = false

    init(_ title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .none
        setButtonType(.pushOnPushOff)
        imagePosition = .noImage
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        ]).width
        return NSSize(width: ceil(textWidth) + 48, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        let track = NSRect(x: 1, y: (bounds.height - 20) / 2, width: 36, height: 20)
        let trackColor = on
            ? SottoTheme.workspaceAccent
            : SottoTheme.workspaceLine.withAlphaComponent(hovering ? 1 : 0.82)
        trackColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10).fill()

        let thumbX = on ? track.maxX - 18 : track.minX + 2
        let thumb = NSRect(x: thumbX, y: track.minY + 2, width: 16, height: 16)
        (on ? NSColor.white : SottoTheme.workspaceSecondaryText).setFill()
        NSBezierPath(ovalIn: thumb).fill()

        let textRect = NSRect(x: 47, y: (bounds.height - 17) / 2,
                              width: max(0, bounds.width - 47), height: 17)
        (title as NSString).draw(in: textRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: isEnabled ? SottoTheme.workspacePrimaryText
                                        : SottoTheme.workspaceSecondaryText,
        ])
    }
}

/// Pop-up behavior remains native, but the field chrome matches the workspace
/// instead of rendering as a light gray AppKit bezel.
final class ThemedPopUpButton: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        bezelStyle = .texturedRounded
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = SottoTheme.workspaceSurface.cgColor
        layer?.borderColor = SottoTheme.workspaceLine.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = SottoTheme.workspaceSecondaryText
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let width = max(super.intrinsicContentSize.width + 14, 150)
        return NSSize(width: width, height: 32)
    }
}

/// Scroll views show the top of each settings page first. AppKit document
/// views otherwise use a bottom-left origin, which is awkward for forms.
private final class SettingsTabDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Tabbed preferences: triggers/history, the ASR engine, and LLM refinement.
/// This is a real resizable window rather than an `NSPanel`: panels retain
/// utility-window chrome and can miss native edge resize hit-testing.
final class SettingsWindow: NSWindow {
    /// Called after Save so the app can reload the key monitor and locale.
    var onSettingsChanged: (() -> Void)?

    // General
    private let holdRecorder = HotkeyRecorderButton()
    private let holdEnabledBox = ThemedToggleButton("启用长按键")
    private let toggleRecorder = HotkeyRecorderButton()
    private let toggleEnabledBox = ThemedToggleButton("启用 Toggle 键")
    private let dashboardRecorder = HotkeyRecorderButton()
    private let dashboardEnabledBox = ThemedToggleButton("启用呼出键")
    private let translateRecorder = HotkeyRecorderButton()
    private let translateEnabledBox = ThemedToggleButton("启用翻译键")
    private let qaRecorder = HotkeyRecorderButton()
    private let qaEnabledBox = ThemedToggleButton("启用问答键")
    private let editLastRecorder = HotkeyRecorderButton()
    private let editLastEnabledBox = ThemedToggleButton("启用修正键")
    private let smartTapBox = ThemedToggleButton("智能点按锁定")
    private let saveHistoryBox = ThemedToggleButton("保存历史记录")
    private let personalizationBox = ThemedToggleButton("从人工修正中学习写作偏好")
    private let appAwareToneBox = ThemedToggleButton("根据当前应用调整语气")
    private let selectionAssistantBox = ThemedToggleButton("问答快捷键启用选中文本助手")
    private let autoLearnDictionaryBox = ThemedToggleButton("从修正中生成词典候选")
    private let whisperModeBox = ThemedToggleButton("轻声模式（提高麦克风增益）")
    private let languagePopup = ThemedPopUpButton()

    // ASR
    private let asrBackendPopup = ThemedPopUpButton()
    private let asrPythonField = NSTextField()
    private let asrModelField = NSTextField()
    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let asrAPIBaseURLField = NSTextField()
    private let asrAPIKeyField = NSTextField()
    private let asrAPIModelField = NSTextField()
    private let asrTestStatusLabel = NSTextField(labelWithString: "")

    // LLM
    private let apiBaseURLField = NSTextField()
    private let apiKeyField = NSTextField()
    private let modelField = NSTextField()
    private let targetLanguageField = NSTextField()
    private let llmEnabledBox = ThemedToggleButton("启用大模型润色")
    private let promptTextView = NSTextView()
    private let hotwordsTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    private let tabSelector = SlidingTabBar(titles: ["通用", "语音模型", "大模型润色"])
    private let contentHost = NSScrollView()
    private var tabViews: [NSView] = []

    private let languages: [(String, String)] = [
        ("自动识别（推荐）", ""),
        ("English (US)", "en-US"),
        ("中文 (简体)", "zh-CN"),
        ("中文 (繁體)", "zh-TW"),
        ("日本語", "ja-JP"),
        ("한국어", "ko-KR"),
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 660),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "Sotto 设置"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = SottoTheme.workspaceBackground
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentMinSize = NSSize(width: 560, height: 600)
        contentMaxSize = NSSize(width: 760, height: 800)
        // WindowResizeView drags the frame directly and clamps against
        // `minSize`/`maxSize`, not `contentMinSize`/`contentMaxSize` — without
        // these the custom edge-drag ignores the intended bounds entirely and
        // the window can be stretched arbitrarily wide.
        minSize = contentMinSize
        maxSize = contentMaxSize
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isEnabled = true
        SottoTheme.applyDarkGlass(to: self)
        setupUI()
        loadSettings()
        center()
        // Bump the autosave key so an older oversized preferences frame does
        // not override the new compact default the first time it opens.
        setFrameAutosaveName("SottoSettingsWindow.v8")
        SottoLog.log(
            "SettingsWindow",
            "created resizable=\(styleMask.contains(.resizable)) frame=\(NSStringFromRect(frame))")
    }

    override var canBecomeKey: Bool { true }

    /// Programmatic tab switch (0=通用 1=语音模型 2=大模型润色) — used by the
    /// `--preview-ui` debug mode to screenshot a specific tab.
    func selectTab(_ index: Int) { tabSelector.select(index) }

    private func setupUI() {
        guard let cv = contentView else { return }

        let title = SottoTheme.displayLabel("Sotto", size: 26)

        let subtitle = NSTextField(labelWithString: "~/.sotto 统一保存配置、提示词和模型")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = SottoTheme.secondaryLabelColor

        let openFolderButton = PillButton(title: "打开 ~/.sotto", style: .neutral, size: .small,
                                          target: self, action: #selector(openSottoFolder))

        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2

        let header = NSStackView(views: [headerText, NSView(), openFolderButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        tabSelector.onSelect = { [weak self] index in self?.showTab(index) }
        tabSelector.translatesAutoresizingMaskIntoConstraints = false

        // The form sits directly on the window background — a big recessed
        // well behind every control read as a rough gray slab, not a surface.
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.borderType = .noBorder
        contentHost.drawsBackground = false
        contentHost.hasVerticalScroller = true
        contentHost.autohidesScrollers = true
        contentHost.hasHorizontalScroller = false

        tabViews = [generalTab(), asrTab(), llmTab()]

        let saveButton = PillButton(title: "保存", style: .primary,
                                    target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let closeButton = PillButton(title: "关闭", style: .neutral,
                                     target: self, action: #selector(closeWindow))

        let buttonRow = NSStackView(views: [NSView(), closeButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(header)
        cv.addSubview(tabSelector)
        cv.addSubview(contentHost)
        cv.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            // Full-size transparent titlebar: leave room for the traffic lights
            // while keeping the titlebar and content on one continuous surface.
            header.topAnchor.constraint(equalTo: cv.topAnchor, constant: 40),
            header.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            tabSelector.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            tabSelector.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            tabSelector.widthAnchor.constraint(equalToConstant: 320),

            contentHost.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: 8),
            contentHost.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            contentHost.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            buttonRow.topAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: 8),
            buttonRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
        ])

        let resizeEdges = WindowResizeView()
        resizeEdges.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(resizeEdges, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            resizeEdges.topAnchor.constraint(equalTo: cv.topAnchor),
            resizeEdges.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            resizeEdges.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            resizeEdges.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
        showTab(0)
    }

    private func showTab(_ index: Int) {
        guard index >= 0, index < tabViews.count else { return }
        let view = tabViews[index]
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.documentView = view
        let clipView = contentHost.contentView
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: clipView.topAnchor),
            view.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            view.widthAnchor.constraint(equalTo: clipView.widthAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualTo: clipView.heightAnchor),
        ])
        // Materialize the incoming tab: a short fade from just below, so the
        // switch reads as content arriving rather than teleporting.
        view.wantsLayer = true
        if let l = view.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.add(fade, forKey: "tabFade")
        }
    }

    private func row(_ label: String, _ control: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: 110).isActive = true
        l.textColor = SottoTheme.secondaryLabelColor
        l.font = .systemFont(ofSize: 12, weight: .medium)
        let s = NSStackView(views: [l, control])
        s.orientation = .horizontal
        s.spacing = 10
        s.alignment = .centerY
        return s
    }

    private func sectionCaption(_ title: String) -> NSTextField {
        let label = SottoTheme.captionLabel(title)
        label.textColor = SottoTheme.workspaceAccent
        return label
    }

    private func generalTab() -> NSView {
        holdRecorder.onCapture = { _ in }
        toggleRecorder.onCapture = { _ in }
        dashboardRecorder.onCapture = { _ in }
        translateRecorder.onCapture = { _ in }
        qaRecorder.onCapture = { _ in }
        editLastRecorder.onCapture = { _ in }
        for p in [languagePopup] { p.translatesAutoresizingMaskIntoConstraints = false }
        for (name, _) in languages { languagePopup.addItem(withTitle: name) }

        let holdRow = NSStackView(views: [holdRecorder, holdEnabledBox])
        holdRow.spacing = 12
        let toggleRow = NSStackView(views: [toggleRecorder, toggleEnabledBox])
        toggleRow.spacing = 12
        let dashboardRow = NSStackView(views: [dashboardRecorder, dashboardEnabledBox])
        dashboardRow.spacing = 12
        let translateRow = NSStackView(views: [translateRecorder, translateEnabledBox])
        translateRow.spacing = 12
        let qaRow = NSStackView(views: [qaRecorder, qaEnabledBox])
        qaRow.spacing = 12
        let editLastRow = NSStackView(views: [editLastRecorder, editLastEnabledBox])
        editLastRow.spacing = 12
        for r in [holdRecorder, toggleRecorder, dashboardRecorder, translateRecorder, qaRecorder,
                  editLastRecorder] {
            r.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        }
        let smartNote = NSTextField(wrappingLabelWithString:
            "快速点按进入持续录音，再点一次结束；长按则松手结束。选中文字后使用问答键，可直接改写、总结、解释或翻译选区。")
        smartNote.font = .systemFont(ofSize: 11)
        smartNote.textColor = SottoTheme.secondaryLabelColor
        smartNote.widthAnchor.constraint(equalToConstant: 450).isActive = true

        let stack = NSStackView(views: [
            sectionCaption("快捷键"),
            row("长按键：", holdRow),
            row("Toggle 键：", toggleRow),
            row("呼出仪表盘：", dashboardRow),
            row("翻译键：", translateRow),
            row("问答键：", qaRow),
            row("修正上一条：", editLastRow),
            smartTapBox,
            smartNote,
            NSBox.separator(),
            sectionCaption("使用偏好"),
            saveHistoryBox,
            appAwareToneBox,
            personalizationBox,
            autoLearnDictionaryBox,
            selectionAssistantBox,
            whisperModeBox,
            row("识别语言：", languagePopup),
        ])
        return wrap(stack)
    }

    private func asrTab() -> NSView {
        asrBackendPopup.addItems(withTitles: ["本地模型（离线）", "OpenAI 兼容接口（在线）"])
        asrBackendPopup.translatesAutoresizingMaskIntoConstraints = false

        asrPythonField.placeholderString = "留空则自动使用内置引擎或开发环境 Python"
        asrModelField.placeholderString = AppSettings.defaultManagedModelURL.path
        asrAPIBaseURLField.placeholderString = "https://api.openai.com/v1"
        asrAPIKeyField.placeholderString = "sk-…（可留空）"
        asrAPIModelField.placeholderString = "whisper-1"
        modelStatusLabel.font = .systemFont(ofSize: 11)
        modelStatusLabel.textColor = SottoTheme.secondaryLabelColor
        modelStatusLabel.lineBreakMode = .byTruncatingMiddle
        modelStatusLabel.widthAnchor.constraint(equalToConstant: 450).isActive = true
        asrTestStatusLabel.font = .systemFont(ofSize: 11)
        asrTestStatusLabel.textColor = SottoTheme.secondaryLabelColor
        asrTestStatusLabel.lineBreakMode = .byTruncatingTail
        asrTestStatusLabel.widthAnchor.constraint(equalToConstant: 450).isActive = true

        let resetModelButton = PillButton(title: "使用默认路径", style: .neutral, size: .small,
                                          target: self, action: #selector(useDefaultModelPath))
        let openModelsButton = PillButton(title: "打开模型目录", style: .neutral, size: .small,
                                          target: self, action: #selector(openModelsFolder))
        let modelButtons = NSStackView(views: [resetModelButton, openModelsButton, NSView()])
        modelButtons.orientation = .horizontal
        modelButtons.spacing = 8

        let note = NSTextField(wrappingLabelWithString:
            "模型默认读取 ~/.sotto/models/Qwen3-ASR-0.6B-8bit。开发机上如果发现 ModelScope 缓存，会在这里创建符号链接，避免复制大文件。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = SottoTheme.secondaryLabelColor
        note.widthAnchor.constraint(equalToConstant: 450).isActive = true

        let remoteNote = NSTextField(wrappingLabelWithString:
            "在线接口调用 {Base URL}/audio/transcriptions（OpenAI Whisper 协议），任何兼容服务均可。切换后立即生效，无需重启。")
        remoteNote.font = .systemFont(ofSize: 11)
        remoteNote.textColor = SottoTheme.secondaryLabelColor
        remoteNote.widthAnchor.constraint(equalToConstant: 450).isActive = true

        let testButton = PillButton(title: "测试连接", style: .neutral, size: .small,
                                    target: self, action: #selector(testRemoteASR))

        let stack = NSStackView(views: [
            row("识别引擎：", asrBackendPopup),
            NSBox.separator(),
            row("Python：", fieldWell(asrPythonField)),
            row("模型路径：", fieldWell(asrModelField)),
            row("", modelButtons),
            modelStatusLabel,
            note,
            NSBox.separator(),
            row("API Base URL：", fieldWell(asrAPIBaseURLField)),
            row("API Key：", fieldWell(asrAPIKeyField)),
            row("在线模型：", fieldWell(asrAPIModelField)),
            row("", testButton),
            asrTestStatusLabel,
            remoteNote,
        ])
        return wrap(stack)
    }

    private func llmTab() -> NSView {
        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "sk-…（可留空）"
        modelField.placeholderString = "gpt-4o-mini"
        targetLanguageField.placeholderString = "English（翻译键的目标语言，自然语言描述即可）"
        let testButton = PillButton(title: "测试连接", style: .neutral, size: .small,
                                    target: self, action: #selector(test))
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = SottoTheme.secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true

        // Editable refine prompt.
        let promptCaption = NSTextField(labelWithString: "润色提示词（可自定义）：")
        promptCaption.font = .systemFont(ofSize: 12)
        let resetPromptBtn = PillButton(title: "恢复默认", style: .neutral, size: .small,
                                        target: self, action: #selector(resetPrompt))
        let promptHeader = NSStackView(views: [promptCaption, NSView(), resetPromptBtn])
        promptHeader.orientation = .horizontal

        let promptScroll = codeEditorScroll(promptTextView, height: 96)

        // Editable hotword list — injected into the refine/translate prompt.
        let hotwordsCaption = NSTextField(labelWithString: "热词表（每行一个词，# 开头为注释，保存后立即生效）：")
        hotwordsCaption.font = .systemFont(ofSize: 12)
        let hotwordsScroll = codeEditorScroll(hotwordsTextView, height: 60)

        let stack = NSStackView(views: [
            llmEnabledBox,
            row("API Base URL：", fieldWell(apiBaseURLField)),
            row("API Key：", fieldWell(apiKeyField)),
            row("模型：", fieldWell(modelField)),
            row("翻译目标语言：", fieldWell(targetLanguageField)),
            row("", testButton),
            statusLabel,
            promptHeader,
            promptScroll,
            hotwordsCaption,
            hotwordsScroll,
        ])
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        promptHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        promptScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hotwordsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return wrap(stack)
    }

    /// A dark, monospaced, plain-text editor in a rounded scroll view — shared
    /// by the refine prompt and the hotword list.
    private func codeEditorScroll(_ textView: NSTextView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        SottoTheme.styleAsWell(scroll, cornerRadius: 10)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        // Without an explicit color the text view falls back to NSColor.textColor,
        // which resolves to near-black against this dark editor background and
        // renders the content invisible. Match the window's light label color.
        textView.textColor = SottoTheme.primaryLabelColor
        textView.insertionPointColor = SottoTheme.primaryLabelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // The document view is sized by the clip view via its autoresizing mask,
        // not Auto Layout. Without `.width` here the text view keeps its initial
        // zero width, so its text container is 0-wide and nothing ever draws
        // (even though the string and color are correct). Give it a real starting
        // width and let it track the clip view horizontally while growing
        // vertically with the text.
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(x: 0, y: 0, width: 480, height: height)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    /// Assign text to a code-editor text view and (re)apply the light color.
    /// A plain (non-rich) NSTextView rebuilds its content from the default
    /// attributes on `.string =`, discarding the `textColor` set at construction
    /// and leaving near-black text on the dark editor. Re-setting `textColor`
    /// afterwards recolors the whole existing range, so the text stays visible.
    private func setEditorText(_ textView: NSTextView, _ text: String) {
        textView.string = text
        textView.textColor = SottoTheme.primaryLabelColor
    }

    @objc private func resetPrompt() {
        setEditorText(promptTextView, LLMRefiner.defaultSystemPrompt)
    }

    @objc private func openSottoFolder() {
        try? FileManager.default.createDirectory(at: SottoConfig.homeDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([SottoConfig.homeDir])
    }

    @objc private func openModelsFolder() {
        try? FileManager.default.createDirectory(at: SottoConfig.modelsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([SottoConfig.modelsDir])
    }

    @objc private func useDefaultModelPath() {
        asrModelField.stringValue = AppSettings.defaultManagedModelURL.path
        updateModelStatus()
    }

    private func wrap(_ stack: NSStackView) -> NSView {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = SettingsTabDocumentView()
        container.addSubview(stack)
        let fittedBottom = stack.bottomAnchor.constraint(
            equalTo: container.bottomAnchor, constant: -14)
        fittedBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 450),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
            fittedBottom,
        ])
        return container
    }

    /// Host a text field inside a styled recessed well, vertically centered by
    /// constraints. The previous approach — forcing the field itself to 32pt
    /// with a custom centering cell — placed the field editor at the top of the
    /// cell, so the text visibly jumped upward the moment a field was clicked.
    private func fieldWell(_ field: NSTextField) -> NSView {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = SottoTheme.workspacePrimaryText
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        if let cell = field.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.wraps = false
        }
        field.translatesAutoresizingMaskIntoConstraints = false

        let well = NSView()
        well.translatesAutoresizingMaskIntoConstraints = false
        SottoTheme.styleAsWell(well, cornerRadius: 8)
        well.addSubview(field)
        NSLayoutConstraint.activate([
            well.heightAnchor.constraint(equalToConstant: 32),
            well.widthAnchor.constraint(equalToConstant: 330),
            field.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])
        return well
    }

    private func updateModelStatus() {
        let path = asrModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = path.isEmpty ? AppSettings.defaultManagedModelURL.path : path
        let exists = FileManager.default.fileExists(atPath: effective)
        modelStatusLabel.stringValue = exists ? "模型已就绪：\(effective)" : "未找到模型：\(effective)"
        modelStatusLabel.textColor = exists ? .systemGreen : .systemOrange
    }

    // MARK: - Load / Save

    private func loadSettings() {
        holdRecorder.hotkey = AppSettings.holdHotkey
        holdEnabledBox.state = AppSettings.holdEnabled ? .on : .off
        toggleRecorder.hotkey = AppSettings.toggleHotkey
        toggleRecorder.placeholder = "未设置"
        toggleEnabledBox.state = AppSettings.toggleEnabled ? .on : .off
        dashboardRecorder.hotkey = AppSettings.dashboardHotkey
        dashboardEnabledBox.state = AppSettings.dashboardEnabled ? .on : .off
        translateRecorder.hotkey = AppSettings.translateHotkey
        translateEnabledBox.state = AppSettings.translateEnabled ? .on : .off
        qaRecorder.hotkey = AppSettings.qaHotkey
        qaEnabledBox.state = AppSettings.qaEnabled ? .on : .off
        editLastRecorder.hotkey = AppSettings.editLastHotkey
        editLastEnabledBox.state = AppSettings.editLastEnabled ? .on : .off
        smartTapBox.state = AppSettings.smartTapToLock ? .on : .off
        saveHistoryBox.state = AppSettings.saveHistory ? .on : .off
        personalizationBox.state = AppSettings.personalizationEnabled ? .on : .off
        appAwareToneBox.state = AppSettings.appAwareToneEnabled ? .on : .off
        selectionAssistantBox.state = AppSettings.selectionAssistantEnabled ? .on : .off
        autoLearnDictionaryBox.state = AppSettings.autoLearnDictionary ? .on : .off
        whisperModeBox.state = AppSettings.whisperModeEnabled ? .on : .off

        let code = AppSettings.localeCode
        if let idx = languages.firstIndex(where: { $0.1 == code }) {
            languagePopup.selectItem(at: idx)
        }

        asrBackendPopup.selectItem(at: AppSettings.asrBackend == .openAI ? 1 : 0)
        asrPythonField.stringValue = AppSettings.asrPythonPath
        asrModelField.stringValue = AppSettings.asrModelPath
        asrAPIBaseURLField.stringValue = AppSettings.asrAPIBaseURL
        asrAPIKeyField.stringValue = AppSettings.asrAPIKey
        asrAPIModelField.stringValue = AppSettings.asrAPIModel
        updateModelStatus()

        let refiner = LLMRefiner.shared
        apiBaseURLField.stringValue = refiner.apiBaseURL
        apiKeyField.stringValue = refiner.apiKey
        modelField.stringValue = refiner.model
        llmEnabledBox.state = refiner.isEnabled ? .on : .off
        setEditorText(promptTextView, refiner.systemPrompt)
        setEditorText(hotwordsTextView, SottoConfig.readHotwordsRaw())
        targetLanguageField.stringValue = refiner.translateTargetLanguage
    }

    @objc private func save() {
        if let hk = holdRecorder.hotkey { AppSettings.holdHotkey = hk }
        AppSettings.holdEnabled = holdEnabledBox.state == .on
        AppSettings.toggleHotkey = toggleRecorder.hotkey
        AppSettings.toggleEnabled = toggleEnabledBox.state == .on
        if let dk = dashboardRecorder.hotkey { AppSettings.dashboardHotkey = dk }
        AppSettings.dashboardEnabled = dashboardEnabledBox.state == .on
        if let tk = translateRecorder.hotkey { AppSettings.translateHotkey = tk }
        AppSettings.translateEnabled = translateEnabledBox.state == .on
        if let qk = qaRecorder.hotkey { AppSettings.qaHotkey = qk }
        AppSettings.qaEnabled = qaEnabledBox.state == .on
        if let ek = editLastRecorder.hotkey { AppSettings.editLastHotkey = ek }
        AppSettings.editLastEnabled = editLastEnabledBox.state == .on
        AppSettings.smartTapToLock = smartTapBox.state == .on
        AppSettings.saveHistory = saveHistoryBox.state == .on
        AppSettings.personalizationEnabled = personalizationBox.state == .on
        AppSettings.appAwareToneEnabled = appAwareToneBox.state == .on
        AppSettings.selectionAssistantEnabled = selectionAssistantBox.state == .on
        AppSettings.autoLearnDictionary = autoLearnDictionaryBox.state == .on
        AppSettings.whisperModeEnabled = whisperModeBox.state == .on

        let idx = languagePopup.indexOfSelectedItem
        if idx >= 0, idx < languages.count {
            AppSettings.localeCode = languages[idx].1
        }

        AppSettings.asrBackend = asrBackendPopup.indexOfSelectedItem == 1 ? .openAI : .local
        AppSettings.asrPythonPath = asrPythonField.stringValue
        AppSettings.asrModelPath = asrModelField.stringValue
        AppSettings.asrAPIBaseURL = asrAPIBaseURLField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.asrAPIKey = asrAPIKeyField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.asrAPIModel = asrAPIModelField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let refiner = LLMRefiner.shared
        refiner.apiBaseURL = apiBaseURLField.stringValue
        refiner.apiKey = apiKeyField.stringValue
        refiner.model = modelField.stringValue
        refiner.isEnabled = llmEnabledBox.state == .on
        refiner.systemPrompt = promptTextView.string
        SottoConfig.writeHotwords(hotwordsTextView.string)
        let lang = targetLanguageField.stringValue.trimmingCharacters(in: .whitespaces)
        refiner.translateTargetLanguage = lang.isEmpty ? "English" : lang

        onSettingsChanged?()
        close()
    }

    @objc private func closeWindow() { close() }

    @objc private func test() {
        // Test with the field values as-is — nothing is persisted until 保存.
        let baseURL = apiBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            showStatus("API Base URL 为空", success: false); return
        }
        showStatus("测试中…", success: nil)
        LLMRefiner.test(text: "派森写了一个阿皮艾",
                        baseURL: baseURL,
                        apiKey: apiKeyField.stringValue,
                        model: modelField.stringValue) { [weak self] result in
            switch result {
            case .success(let text): self?.showStatus("OK：\(text)", success: true)
            case .failure(let error): self?.showStatus(error.localizedDescription, success: false)
            }
        }
    }

    @objc private func testRemoteASR() {
        // Test with the field values as-is — nothing is persisted until 保存.
        let baseURL = asrAPIBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            showASRStatus("API Base URL 为空", success: false); return
        }
        showASRStatus("测试中…", success: nil)
        RemoteASRClient.test(
            baseURL: baseURL,
            apiKey: asrAPIKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: asrAPIModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { [weak self] result in
            switch result {
            case .success(let text):
                self?.showASRStatus("连接正常" + (text.isEmpty ? "" : "：\(text)"), success: true)
            case .failure(let error):
                self?.showASRStatus(error.localizedDescription, success: false)
            }
        }
    }

    private func showASRStatus(_ text: String, success: Bool?) {
        asrTestStatusLabel.stringValue = text
        switch success {
        case .some(true): asrTestStatusLabel.textColor = .systemGreen
        case .some(false): asrTestStatusLabel.textColor = .systemRed
        case .none: asrTestStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func showStatus(_ text: String, success: Bool?) {
        statusLabel.stringValue = text
        statusLabel.isHidden = false
        switch success {
        case .some(true): statusLabel.textColor = .systemGreen
        case .some(false): statusLabel.textColor = .systemRed
        case .none: statusLabel.textColor = .secondaryLabelColor
        }
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return b
    }
}
