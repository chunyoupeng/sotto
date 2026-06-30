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

    private static let relevantMods: UInt64 =
        CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        title = recording ? "按下快捷键…（Esc 取消）" : (hotkey?.displayString ?? placeholder)
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
        // flagsChanged: Fn or a bare modifier key.
        let flags = event.modifierFlags
        if flags.contains(.function) {
            commit(.fn)
            return
        }
        let code = Int(event.keyCode)
        if let modFlag = Hotkey.modifierFlag(forKeyCode: code) {
            // Only capture on press (flag now set).
            let cg = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            if cg.contains(modFlag) {
                commit(Hotkey(keyCode: code, modifiers: 0))
            }
        }
    }

    private func commit(_ hk: Hotkey) {
        hotkey = hk
        endRecording()
        onCapture?(hk)
    }
}

/// Tabbed preferences: triggers/history, the ASR engine, and LLM refinement.
final class SettingsWindow: NSPanel {
    /// Called after Save so the app can reload the key monitor and locale.
    var onSettingsChanged: (() -> Void)?

    // General
    private let holdRecorder = HotkeyRecorderButton()
    private let holdEnabledBox = NSButton(checkboxWithTitle: "启用长按键", target: nil, action: nil)
    private let toggleRecorder = HotkeyRecorderButton()
    private let toggleEnabledBox = NSButton(checkboxWithTitle: "启用 Toggle 键", target: nil, action: nil)
    private let dashboardRecorder = HotkeyRecorderButton()
    private let dashboardEnabledBox = NSButton(checkboxWithTitle: "启用呼出键", target: nil, action: nil)
    private let smartTapBox = NSButton(checkboxWithTitle: "智能点按锁定", target: nil, action: nil)
    private let saveHistoryBox = NSButton(checkboxWithTitle: "保存历史记录", target: nil, action: nil)
    private let saveAudioBox = NSButton(checkboxWithTitle: "保存录音音频", target: nil, action: nil)
    private let languagePopup = NSPopUpButton()

    // ASR
    private let asrPythonField = NSTextField()
    private let asrModelField = NSTextField()
    private let modelStatusLabel = NSTextField(labelWithString: "")

    // LLM
    private let apiBaseURLField = NSTextField()
    private let apiKeyField = NSTextField()
    private let modelField = NSTextField()
    private let llmEnabledBox = NSButton(checkboxWithTitle: "启用大模型润色", target: nil, action: nil)
    private let promptTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    private let tabSelector = NSSegmentedControl(
        labels: ["通用", "语音模型", "大模型润色"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let contentHost = NSView()
    private var tabViews: [NSView] = []

    private let languages: [(String, String)] = [
        ("跟随系统", ""),
        ("English (US)", "en-US"),
        ("中文 (简体)", "zh-CN"),
        ("中文 (繁體)", "zh-TW"),
        ("日本語", "ja-JP"),
        ("한국어", "ko-KR"),
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        title = "Sotto 设置"
        isReleasedWhenClosed = false
        SottoTheme.applyDarkGlass(to: self)
        setupUI()
        loadSettings()
        center()
    }

    override var canBecomeKey: Bool { true }

    private func setupUI() {
        guard let cv = contentView else { return }

        let title = NSTextField(labelWithString: "Sotto")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        title.textColor = SottoTheme.primaryLabelColor

        let subtitle = NSTextField(labelWithString: "~/.sotto 统一保存配置、提示词和模型")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = SottoTheme.secondaryLabelColor

        let openFolderButton = NSButton(title: "打开 ~/.sotto", target: self, action: #selector(openSottoFolder))
        openFolderButton.bezelStyle = .rounded
        openFolderButton.controlSize = .small

        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2

        let header = NSStackView(views: [headerText, NSView(), openFolderButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        tabSelector.target = self
        tabSelector.action = #selector(tabChanged)
        tabSelector.selectedSegment = 0
        tabSelector.segmentStyle = .texturedRounded
        tabSelector.translatesAutoresizingMaskIntoConstraints = false

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.wantsLayer = true
        contentHost.layer?.cornerRadius = 8
        contentHost.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        contentHost.layer?.borderWidth = 0.5
        contentHost.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        tabViews = [generalTab(), asrTab(), llmTab()]

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.contentTintColor = NSColor(cgColor: SottoTheme.accent)
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [NSView(), closeButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(header)
        cv.addSubview(tabSelector)
        cv.addSubview(contentHost)
        cv.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cv.topAnchor, constant: 22),
            header.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),

            tabSelector.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            tabSelector.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            tabSelector.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -24),
            tabSelector.widthAnchor.constraint(equalToConstant: 360),

            contentHost.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: 14),
            contentHost.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            contentHost.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
            buttonRow.topAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: 14),
            buttonRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -18),
        ])
        showTab(0)
    }

    @objc private func tabChanged() {
        showTab(tabSelector.selectedSegment)
    }

    private func showTab(_ index: Int) {
        guard index >= 0, index < tabViews.count else { return }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let view = tabViews[index]
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
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

    private func generalTab() -> NSView {
        holdRecorder.onCapture = { _ in }
        toggleRecorder.onCapture = { _ in }
        dashboardRecorder.onCapture = { _ in }
        for p in [languagePopup] { p.translatesAutoresizingMaskIntoConstraints = false }
        for (name, _) in languages { languagePopup.addItem(withTitle: name) }

        let holdRow = NSStackView(views: [holdRecorder, holdEnabledBox])
        holdRow.spacing = 12
        let toggleRow = NSStackView(views: [toggleRecorder, toggleEnabledBox])
        toggleRow.spacing = 12
        let dashboardRow = NSStackView(views: [dashboardRecorder, dashboardEnabledBox])
        dashboardRow.spacing = 12
        for r in [holdRecorder, toggleRecorder, dashboardRecorder] {
            r.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        }
        let smartNote = NSTextField(wrappingLabelWithString: "快速点按进入持续录音，再点一次结束；长按则松手结束。")
        smartNote.font = .systemFont(ofSize: 11)
        smartNote.textColor = SottoTheme.secondaryLabelColor

        let stack = NSStackView(views: [
            row("长按键：", holdRow),
            row("Toggle 键：", toggleRow),
            row("呼出仪表盘：", dashboardRow),
            smartTapBox,
            smartNote,
            NSBox.separator(),
            saveHistoryBox,
            saveAudioBox,
            row("识别语言：", languagePopup),
        ])
        return wrap(stack)
    }

    private func asrTab() -> NSView {
        asrPythonField.placeholderString = "留空则自动使用内置引擎或开发环境 Python"
        asrModelField.placeholderString = AppSettings.defaultManagedModelURL.path
        for f in [asrPythonField, asrModelField] {
            styleTextField(f)
            f.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        }
        modelStatusLabel.font = .systemFont(ofSize: 11)
        modelStatusLabel.textColor = SottoTheme.secondaryLabelColor

        let resetModelButton = NSButton(title: "使用默认路径", target: self, action: #selector(useDefaultModelPath))
        let openModelsButton = NSButton(title: "打开模型目录", target: self, action: #selector(openModelsFolder))
        for b in [resetModelButton, openModelsButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        let modelButtons = NSStackView(views: [resetModelButton, openModelsButton, NSView()])
        modelButtons.orientation = .horizontal
        modelButtons.spacing = 8

        let note = NSTextField(wrappingLabelWithString:
            "模型默认读取 ~/.sotto/models/Qwen3-ASR-0.6B-8bit。开发机上如果发现 ModelScope 缓存，会在这里创建符号链接，避免复制大文件。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = SottoTheme.secondaryLabelColor

        let stack = NSStackView(views: [
            row("Python：", asrPythonField),
            row("模型路径：", asrModelField),
            row("", modelButtons),
            modelStatusLabel,
            note,
        ])
        return wrap(stack)
    }

    private func llmTab() -> NSView {
        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "sk-…（可留空）"
        modelField.placeholderString = "gpt-4o-mini"
        for f in [apiBaseURLField, apiKeyField, modelField] {
            styleTextField(f)
            f.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        }
        let testButton = NSButton(title: "测试", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = SottoTheme.secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        // Editable refine prompt.
        let promptCaption = NSTextField(labelWithString: "润色提示词（可自定义）：")
        promptCaption.font = .systemFont(ofSize: 12)
        let resetPromptBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetPrompt))
        resetPromptBtn.bezelStyle = .rounded
        resetPromptBtn.controlSize = .small
        let promptHeader = NSStackView(views: [promptCaption, NSView(), resetPromptBtn])
        promptHeader.orientation = .horizontal

        let promptScroll = NSScrollView()
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .noBorder
        promptScroll.drawsBackground = false
        promptScroll.wantsLayer = true
        promptScroll.layer?.cornerRadius = 8
        promptScroll.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        promptScroll.layer?.borderWidth = 0.5
        promptScroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        promptScroll.documentView = promptTextView
        promptTextView.isRichText = false
        promptTextView.drawsBackground = false
        promptTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        promptTextView.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView.isAutomaticDashSubstitutionEnabled = false
        promptTextView.isVerticallyResizable = true
        promptTextView.isHorizontallyResizable = false
        promptTextView.textContainer?.widthTracksTextView = true
        promptScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let stack = NSStackView(views: [
            llmEnabledBox,
            row("API Base URL：", apiBaseURLField),
            row("API Key：", apiKeyField),
            row("模型：", modelField),
            row("", testButton),
            statusLabel,
            promptHeader,
            promptScroll,
        ])
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        promptHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        promptScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return wrap(stack)
    }

    @objc private func resetPrompt() {
        promptTextView.string = LLMRefiner.defaultSystemPrompt
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
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -22),
        ])
        return container
    }

    private func styleTextField(_ field: NSTextField) {
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 12)
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
        smartTapBox.state = AppSettings.smartTapToLock ? .on : .off
        saveHistoryBox.state = AppSettings.saveHistory ? .on : .off
        saveAudioBox.state = AppSettings.saveAudio ? .on : .off

        let code = AppSettings.localeCode
        if let idx = languages.firstIndex(where: { $0.1 == code }) {
            languagePopup.selectItem(at: idx)
        }

        asrPythonField.stringValue = AppSettings.asrPythonPath
        asrModelField.stringValue = AppSettings.asrModelPath
        updateModelStatus()

        let refiner = LLMRefiner.shared
        apiBaseURLField.stringValue = refiner.apiBaseURL
        apiKeyField.stringValue = refiner.apiKey
        modelField.stringValue = refiner.model
        llmEnabledBox.state = refiner.isEnabled ? .on : .off
        promptTextView.string = refiner.systemPrompt
    }

    @objc private func save() {
        if let hk = holdRecorder.hotkey { AppSettings.holdHotkey = hk }
        AppSettings.holdEnabled = holdEnabledBox.state == .on
        AppSettings.toggleHotkey = toggleRecorder.hotkey
        AppSettings.toggleEnabled = toggleEnabledBox.state == .on
        if let dk = dashboardRecorder.hotkey { AppSettings.dashboardHotkey = dk }
        AppSettings.dashboardEnabled = dashboardEnabledBox.state == .on
        AppSettings.smartTapToLock = smartTapBox.state == .on
        AppSettings.saveHistory = saveHistoryBox.state == .on
        AppSettings.saveAudio = saveAudioBox.state == .on

        let idx = languagePopup.indexOfSelectedItem
        if idx >= 0, idx < languages.count {
            AppSettings.localeCode = languages[idx].1
        }

        AppSettings.asrPythonPath = asrPythonField.stringValue
        AppSettings.asrModelPath = asrModelField.stringValue

        let refiner = LLMRefiner.shared
        refiner.apiBaseURL = apiBaseURLField.stringValue
        refiner.apiKey = apiKeyField.stringValue
        refiner.model = modelField.stringValue
        refiner.isEnabled = llmEnabledBox.state == .on
        refiner.systemPrompt = promptTextView.string

        onSettingsChanged?()
        close()
    }

    @objc private func closeWindow() { close() }

    @objc private func test() {
        let refiner = LLMRefiner.shared
        refiner.apiBaseURL = apiBaseURLField.stringValue
        refiner.apiKey = apiKeyField.stringValue
        refiner.model = modelField.stringValue
        guard refiner.isConfigured else {
            showStatus("API Base URL 为空", success: false); return
        }
        showStatus("测试中…", success: nil)
        refiner.refine("派森写了一个阿皮艾", force: true) { [weak self] result in
            switch result {
            case .success(let text): self?.showStatus("OK：\(text)", success: true)
            case .failure(let error): self?.showStatus(error.localizedDescription, success: false)
            }
        }
    }

    private func showStatus(_ text: String, success: Bool?) {
        statusLabel.stringValue = text
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
