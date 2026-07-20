import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let speechEngine = SpeechEngine()
    private let textInjector = TextInjector()
    private let muteGuard = SystemMuteGuard()
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true

    // Recording state machine.
    private enum RecState { case idle, holding, locked }
    private var recState: RecState = .idle
    private var holdStart: Date?

    /// What the current capture session's result is for: typing the polished
    /// transcript, typing a translation, or answering a spoken question.
    private enum CaptureMode { case dictation, translate, qa }
    private struct FinishContext {
        let mode: CaptureMode
        let frontApp: String?
        let selection: SelectionSnapshot?
    }
    private var captureMode: CaptureMode = .dictation
    /// Name of the app being dictated into, captured when recording starts
    /// (the overlay is non-activating, so it's still frontmost then).
    private var captureFrontApp: String?
    /// Optional selection captured at the exact moment a QA session starts.
    /// It is revalidated before any replacement after the network round-trip.
    private var captureSelection: SelectionSnapshot?
    /// ASR results may complete after a second recording has already begun.
    /// Route each result by its unique WAV instead of a shared mutable mode.
    private var pendingFinishContexts: [String: FinishContext] = [:]
    private lazy var qaPanel = QAPanel()

    private lazy var settingsWindow = SettingsWindow()
    private lazy var dashboardWindowVC = DashboardViewController()
    private var dashboardWindow: NSWindow?

    private var selectedLocaleCode: String { AppSettings.localeCode }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let code = selectedLocaleCode
        speechEngine.automaticallyDetectsLanguage = code.isEmpty
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)

        // Touch the store eagerly so its one-time data-dir migration
        // (VoiceInput → Sotto) runs at launch rather than on first dashboard open.
        _ = RecordStore.shared

        setupMainMenu()
        setupStatusBar()
        setupSpeechCallbacks()
        showMainWindow()

        settingsWindow.onSettingsChanged = { [weak self] in self?.reloadFromSettings() }

        SpeechEngine.requestPermissions { [weak self] granted, errorMsg in
            if !granted, let msg = errorMsg {
                self?.showAlert(title: "Permission Required", message: msg)
            }
        }

        keyMonitor.onHoldDown = { [weak self] in self?.handleHoldDown() }
        keyMonitor.onHoldUp = { [weak self] in self?.handleHoldUp() }
        keyMonitor.onToggleDown = { [weak self] in self?.handleToggle() }
        keyMonitor.onDashboardDown = { [weak self] in self?.toggleDashboardWindow() }
        keyMonitor.onTranslateDown = { [weak self] in self?.handleTranslateDown() }
        keyMonitor.onTranslateUp = { [weak self] in self?.handleTranslateUp() }
        keyMonitor.onQADown = { [weak self] in self?.handleQADown() }
        keyMonitor.onQAUp = { [weak self] in self?.handleQAUp() }
        keyMonitor.onEditLastDown = { [weak self] in self?.editLastRecord() }
        if !keyMonitor.start() {
            showAccessibilityAlert()
        }

        // Pause the global tap while a hotkey is being recorded in Settings.
        NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingStarted, object: nil, queue: .main) { [weak self] _ in
            self?.keyMonitor.stop()
        }
        NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingStopped, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            _ = self.keyMonitor.start()
        }
    }

    private func reloadFromSettings() {
        keyMonitor.reload()
        let code = selectedLocaleCode
        speechEngine.automaticallyDetectsLanguage = code.isEmpty
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)
        speechEngine.applyBackendSelection()
    }

    // MARK: - Trigger handling

    private func handleHoldDown() {
        guard isEnabled else { return }
        switch recState {
        case .idle: startCapture(locked: false)
        case .locked:
            // Pressing the hold key again ends a locked *dictation* session.
            // Locked translate/QA sessions are ended by their own chord —
            // if the hold key (the chord's Fn half) ended them, the chord's
            // second key would land on an idle state and instantly start a
            // fresh capture.
            if captureMode == .dictation { stopAndFinish() }
        case .holding: break
        }
    }

    private func handleHoldUp() {
        guard recState == .holding else { return }
        let elapsed = holdStart.map { Date().timeIntervalSince($0) } ?? .infinity
        if AppSettings.smartTapToLock && elapsed < AppSettings.tapThreshold {
            // Quick tap → keep recording until tapped again.
            recState = .locked
            overlayPanel.updateText("持续聆听…")
        } else {
            stopAndFinish()
        }
    }

    private func handleToggle() {
        guard isEnabled else { return }
        if recState == .idle { startCapture(locked: true) }
        else { stopAndFinish() }
    }

    /// True when the translate hotkey itself started the capture (as opposed
    /// to upgrading a session the hold key had already started). Decides
    /// which key's release ends the session.
    private var translateChordInitiated = false

    /// Translate chord pressed. Idle → start a translate capture; while a
    /// dictation capture is running (e.g. the chord shares Fn with the hold
    /// key and Fn landed first) → upgrade the session to translate mode.
    private func handleTranslateDown() {
        guard isEnabled else { return }
        switch recState {
        case .idle:
            startCapture(locked: false, mode: .translate)
            translateChordInitiated = recState != .idle  // capture actually started
        case .holding, .locked:
            if captureMode == .translate {
                // Second tap of the chord ends a locked translate session.
                if recState == .locked { stopAndFinish() }
            } else if captureMode == .dictation {
                captureMode = .translate
                applyOverlayAccent(for: .translate)
                overlayPanel.updateText(listeningText(for: .translate))
            }
        }
    }

    private func handleTranslateUp() {
        // In an upgraded session the hold key's own release ends it (releasing
        // just the chord's other half keeps recording); only a chord-initiated
        // session reacts here — with the same smart tap-to-lock as the hold key.
        guard translateChordInitiated, recState == .holding, captureMode == .translate else { return }
        let elapsed = holdStart.map { Date().timeIntervalSince($0) } ?? .infinity
        if AppSettings.smartTapToLock && elapsed < AppSettings.tapThreshold {
            recState = .locked
            overlayPanel.updateText("持续聆听 · 翻译（再按一次结束）")
        } else {
            stopAndFinish()
        }
    }

    /// QA chord pressed. Like translate, the default chord shares Fn with the
    /// hold key, so Fn landing first may already have started a dictation
    /// capture — upgrade it instead of ignoring the press.
    private func handleQADown() {
        guard isEnabled else { return }
        switch recState {
        case .idle:
            startCapture(locked: false, mode: .qa)
        case .holding, .locked:
            if captureMode == .qa {
                // Second tap of the chord ends a locked QA session.
                if recState == .locked { stopAndFinish() }
            } else if captureMode == .dictation {
                captureMode = .qa
                captureSelection = AppSettings.selectionAssistantEnabled ? SelectionContext.capture() : nil
                applyOverlayAccent(for: .qa)
                overlayPanel.updateText(listeningText(for: .qa))
            }
        }
    }

    /// Same smart tap-to-lock as the hold key: a quick tap of the chord keeps
    /// listening (tap again to finish), a real hold stops on release — so a
    /// tap never commits a fraction of a second of nothing.
    private func handleQAUp() {
        guard recState == .holding, captureMode == .qa else { return }
        let elapsed = holdStart.map { Date().timeIntervalSince($0) } ?? .infinity
        if AppSettings.smartTapToLock && elapsed < AppSettings.tapThreshold {
            recState = .locked
            overlayPanel.updateText("持续聆听 · 问答（再按一次结束）")
        } else {
            stopAndFinish()
        }
    }

    // MARK: - Capture lifecycle

    private func startCapture(locked: Bool, mode: CaptureMode = .dictation) {
        guard isEnabled, recState == .idle else { return }
        LLMRefiner.shared.cancel()
        recState = locked ? .locked : .holding
        holdStart = Date()
        captureMode = mode
        translateChordInitiated = false
        captureFrontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        captureSelection = mode == .qa && AppSettings.selectionAssistantEnabled
            ? SelectionContext.capture() : nil
        updateStatusIcon(recording: true)
        applyOverlayAccent(for: mode)
        overlayPanel.show(text: listeningText(for: mode))
        SoundFX.playPress()
        speechEngine.startRecording()
        // Mute the speakers while the mic is open — but only after the press
        // tick has had time to sound (it plays through the same output).
        if AppSettings.muteWhileRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.recState != .idle else { return }
                self.muteGuard.mute()
            }
        }
    }

    private func listeningText(for mode: CaptureMode) -> String {
        switch mode {
        case .dictation: return "正在聆听…"
        case .translate: return "正在聆听 · 翻译 → \(LLMRefiner.shared.translateTargetLanguage)"
        case .qa:
            return captureSelection == nil ? "正在聆听 · 问答" : "正在聆听 · 选区助手"
        }
    }

    /// Light style per capture mode: spectral rainbow = dictation, green =
    /// translate, pink = QA — the color tells the mode at a glance.
    private func applyOverlayAccent(for mode: CaptureMode) {
        switch mode {
        case .dictation: overlayPanel.setCaptureStyle(.dictation)
        case .translate: overlayPanel.setCaptureStyle(.translate)
        case .qa: overlayPanel.setCaptureStyle(.qa)
        }
    }

    private func stopAndFinish() {
        guard recState != .idle else { return }
        recState = .idle
        holdStart = nil
        let context = FinishContext(
            mode: captureMode, frontApp: captureFrontApp, selection: captureSelection)
        captureSelection = nil
        updateStatusIcon(recording: false)
        // Restore output before the release cue. Otherwise the paired feedback
        // sound is inaudible and the user's Mac can remain muted.
        muteGuard.unmute()
        SoundFX.playRelease()
        guard let audioURL = speechEngine.stopRecording() else {
            dismissWithNotice("录音未能完成")
            return
        }
        pendingFinishContexts[audioURL.standardizedFileURL.path] = context
        overlayPanel.showTranscribing()
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechEngine.onFinalResultFull = { [weak self] raw, audioURL, duration in
            guard let self, let audioURL else { return }
            let key = audioURL.standardizedFileURL.path
            guard let context = self.pendingFinishContexts.removeValue(forKey: key) else {
                try? FileManager.default.removeItem(at: audioURL)
                SottoLog.log("AppDelegate", "discarded ASR result with no finish context")
                return
            }
            self.handleFinal(raw: raw, audioURL: audioURL, duration: duration, context: context)
        }

        speechEngine.onError = { [weak self] msg in
            guard let self else { return }
            self.recState = .idle
            self.muteGuard.unmute()
            self.overlayPanel.showError("出错：\(msg)")
            self.overlayPanel.dismiss(after: 1.5)
        }

        speechEngine.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }
    }

    private func handleFinal(raw: String, audioURL: URL?, duration: TimeInterval,
                             context: FinishContext) {
        let rawText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            if let u = audioURL { try? FileManager.default.removeItem(at: u) }
            dismissWithNotice("未听到任何声音")
            return
        }

        switch context.mode {
        case .dictation:
            finishDictation(rawText: rawText, audioURL: audioURL, duration: duration,
                            frontApp: context.frontApp)
        case .translate:
            finishTranslate(rawText: rawText, audioURL: audioURL, duration: duration,
                            frontApp: context.frontApp)
        case .qa:
            finishQA(rawText: rawText, audioURL: audioURL,
                     selection: context.selection, frontApp: context.frontApp)
        }
    }

    private func finishDictation(rawText: String, audioURL: URL?, duration: TimeInterval,
                                 frontApp: String?) {
        let refiner = LLMRefiner.shared
        if refiner.isEnabled && refiner.isConfigured {
            overlayPanel.showRefining()
            refiner.refine(rawText, frontApp: frontApp) { [weak self] result in
                guard let self else { return }
                let refined: String
                switch result {
                case .success(let r): refined = r.isEmpty ? rawText : r
                case .failure(LLMRefiner.RefinerError.cancelled):
                    // A new recording started and deliberately cancelled this
                    // refine — discard the utterance entirely. Committing the raw
                    // text here would type it mid-recording and clobber the new
                    // session's "listening" overlay.
                    if let u = audioURL { try? FileManager.default.removeItem(at: u) }
                    return
                case .failure(let e):
                    NSLog("[LLMRefiner] refine failed: %@", e.localizedDescription)
                    refined = rawText
                }
                self.commitResult(raw: rawText, refined: refined, audioURL: audioURL, duration: duration)
            }
        } else {
            commitResult(raw: rawText, refined: rawText, audioURL: audioURL, duration: duration)
        }
    }

    private func finishTranslate(rawText: String, audioURL: URL?, duration: TimeInterval,
                                 frontApp: String?) {
        let refiner = LLMRefiner.shared
        guard refiner.isConfigured else {
            if let u = audioURL { try? FileManager.default.removeItem(at: u) }
            dismissWithNotice("翻译需要先在设置中配置大模型")
            return
        }
        overlayPanel.showRefining("翻译中…")
        refiner.translate(rawText, frontApp: frontApp) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let translated) where !translated.isEmpty:
                self.commitResult(raw: rawText, refined: translated,
                                  audioURL: audioURL, duration: duration)
            case .failure(LLMRefiner.RefinerError.cancelled):
                if let u = audioURL { try? FileManager.default.removeItem(at: u) }
            default:
                // Typing the untranslated original into a foreign-language
                // context is worse than typing nothing — notify and drop.
                if let u = audioURL { try? FileManager.default.removeItem(at: u) }
                self.dismissWithNotice("翻译失败")
            }
        }
    }

    private func finishQA(rawText: String, audioURL: URL?, selection: SelectionSnapshot?,
                          frontApp: String?) {
        // QA never touches the target document or history — the answer only
        // lives in the floating panel.
        if let u = audioURL { try? FileManager.default.removeItem(at: u) }
        let refiner = LLMRefiner.shared
        guard refiner.isConfigured else {
            dismissWithNotice("问答需要先在设置中配置大模型")
            return
        }
        if let selection {
            finishSelectionCommand(rawText, selection: selection, refiner: refiner,
                                   fallbackFrontApp: frontApp)
            return
        }
        // A question asked while the panel is still open continues the
        // conversation with context; a question asked after it was dismissed
        // (Esc/✕ → not visible) starts a fresh session with an empty transcript.
        if !qaPanel.isVisible {
            refiner.resetQAConversation()
            qaPanel.clearTranscript()
        }
        overlayPanel.showRefining("思考中…")
        refiner.answer(rawText) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let answer) where !answer.isEmpty:
                self.overlayPanel.dismiss()
                self.qaPanel.present(question: rawText, answer: answer)
            case .failure(LLMRefiner.RefinerError.cancelled):
                break
            default:
                self.dismissWithNotice("回答失败")
            }
        }
    }

    private func finishSelectionCommand(
        _ command: String, selection: SelectionSnapshot, refiner: LLMRefiner,
        fallbackFrontApp: String?
    ) {
        switch SelectionContext.intent(for: command) {
        case .rewrite:
            overlayPanel.showRefining("正在改写选中文字…")
            refiner.rewriteSelection(
                selectedText: selection.text,
                command: command,
                frontApp: selection.appName ?? fallbackFrontApp
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let replacement) where !replacement.isEmpty:
                    if selection.replace(with: replacement) {
                        self.overlayPanel.showResult(replacement)
                        NSSound(named: .init("Pop"))?.play()
                        self.overlayPanel.dismiss()
                    } else {
                        self.overlayPanel.dismiss()
                        self.qaPanel.present(
                            question: "选区已变化，未自动替换",
                            answer: replacement
                        )
                    }
                case .failure(LLMRefiner.RefinerError.cancelled):
                    break
                default:
                    self.dismissWithNotice("选区改写失败")
                }
            }
        case .ask:
            overlayPanel.showRefining("正在阅读选中文字…")
            refiner.askSelection(
                selectedText: selection.text,
                question: command,
                frontApp: selection.appName ?? fallbackFrontApp
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let answer) where !answer.isEmpty:
                    self.overlayPanel.dismiss()
                    self.qaPanel.present(question: command, answer: answer)
                case .failure(LLMRefiner.RefinerError.cancelled):
                    break
                default:
                    self.dismissWithNotice("选区问答失败")
                }
            }
        }
    }

    private func commitResult(raw: String, refined: String, audioURL: URL?, duration: TimeInterval) {
        // Filler-only utterances: the refiner returns "无" (or nothing) when the
        // input was just hesitation sounds. Don't type that into the document or
        // clutter history — just flag it and back out.
        let finalText = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty || finalText == "无" {
            if let u = audioURL { try? FileManager.default.removeItem(at: u) }
            dismissWithNotice("无实质内容")
            return
        }

        if AppSettings.saveHistory {
            RecordStore.shared.add(rawText: raw, refinedText: refined, duration: duration)
        }
        if let u = audioURL { try? FileManager.default.removeItem(at: u) }

        // Inject immediately — the overlay is a non-activating panel, so focus
        // never left the target field and there is nothing to wait for. The
        // typed text (plus the Pop sound) is the feedback, so the overlay can
        // go right away; the fade-out still flashes the result briefly.
        overlayPanel.showResult(refined)
        textInjector.inject(refined)
        NSSound(named: .init("Pop"))?.play()
        overlayPanel.dismiss()

        if let win = dashboardWindow, win.isVisible { dashboardWindowVC.refresh() }
    }

    /// Briefly flash a non-error notice in the overlay (no speech heard, or the
    /// utterance was filler-only) instead of vanishing silently, then dismiss —
    /// so "nothing to type" still reads as "Sotto heard you," not "Sotto froze."
    private func dismissWithNotice(_ text: String) {
        overlayPanel.showCancelled(text)
        overlayPanel.dismiss(after: 0.45)
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(recording: false)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func updateStatusIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        // Use a waveform glyph (matching the app icon) instead of `mic`, which
        // is visually identical to macOS's built-in dictation menu-bar item.
        let name = recording ? "waveform.circle.fill" : "waveform"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Sotto")?
            .withSymbolConfiguration(config) {
            button.image = image
            button.title = ""
        } else {
            // Text fallback so the item is always visible even if the SF Symbol
            // fails to render.
            button.image = nil
            button.title = recording ? "🔴" : "〰️"
        }
        button.contentTintColor = recording ? .systemRed : nil
    }

    /// Left click summons the main window (the old popover duplicated it);
    /// right click shows the basic menu (settings, quit, …).
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleDashboardWindow()
        }
    }

    // MARK: - Dashboard

    /// The real, ⌘-Tab-switchable main window. Created lazily and reused.
    private func mainWindowIfNeeded() -> NSWindow {
        if let existing = dashboardWindow { return existing }
        dashboardWindowVC.onOpenSettings = { [weak self] in self?.openSettings() }
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        // Start close to the screen's usable size so the overview's lower
        // cards are visible without immediately having to resize or scroll.
        let defaultSize = NSSize(
            width: min(1280, max(860, visible.width - 24)),
            height: min(900, max(560, visible.height - 24)))
        let style: NSWindow.StyleMask = [
            .titled, .closable, .fullSizeContentView,
        ]
        // Create the window with its final style mask. Mutating the convenience
        // `contentViewController` window afterwards can leave its native frame
        // hit-testing region in the original configuration on some macOS builds.
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: style, backing: .buffered, defer: false)
        win.contentViewController = dashboardWindowVC
        // openless-style chrome: the content is the window — no title bar band,
        // no divider under it; the traffic lights float over the sidebar.
        win.title = "Sotto"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        // Let AppKit own the border/corner mouse regions. Whole-background
        // dragging can steal those events in a full-size-content window.
        win.isMovableByWindowBackground = false
        win.backgroundColor = SottoTheme.workspaceBackground
        win.contentMinSize = NSSize(width: 860, height: 560)
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isEnabled = true
        // Bump the key so an older, smaller saved frame does not override the
        // new default on the first launch after this layout update.
        let frameName = "SottoMainWindow.v4"
        if !win.setFrameUsingName(frameName) {
            win.setContentSize(defaultSize)
            win.center()
        }
        win.setFrameAutosaveName(frameName)
        SottoLog.log(
            "MainWindow",
            "created resizable=\(win.styleMask.contains(.resizable)) frame=\(NSStringFromRect(win.frame))")
        dashboardWindow = win
        return win
    }

    /// Bring the main window to the front (creating it if needed) and refresh it.
    private func showMainWindow() {
        let win = mainWindowIfNeeded()
        dashboardWindowVC.refresh()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Global-hotkey entry point: toggle the main window's visibility.
    private func toggleDashboardWindow() {
        if let win = dashboardWindow, win.isVisible {
            win.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    /// Global-hotkey entry point: pop the correction editor for the most recent
    /// dictation, so a bad result can be fixed without opening the dashboard
    /// and hunting for the record. Saving feeds the same personalization flow
    /// as editing from history.
    private func editLastRecord() {
        guard recState == .idle else { return }
        guard let record = RecordStore.shared.recent(limit: 1).first else {
            NSSound(named: .init("Funk"))?.play()
            return
        }
        RecordEditorWindowController.present(for: record) { [weak self] corrected in
            RecordStore.shared.setCorrection(id: record.id, correctedText: corrected)
            guard let self, let win = self.dashboardWindow, win.isVisible else { return }
            self.dashboardWindowVC.refresh()
        }
    }

    /// Clicking the Dock icon (or otherwise reopening) shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Main menu

    /// A minimal but standard main menu so Sotto behaves like a real app: an app
    /// menu (Quit/Settings), an Edit menu (cut/copy/paste/undo — needed by the
    /// record editor's text view), and a Window menu.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 Sotto", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Sotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)

        // Edit menu — wires up the standard responder-chain text actions.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu (right-click)

    private func showMenu() {
        let menu = NSMenu()

        let enableItem = NSMenuItem(title: "已启用", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = isEnabled ? .on : .off
        menu.addItem(enableItem)

        menu.addItem(.separator())

        // Quick ASR backend switch, mirroring 设置 → 语音模型 → 识别引擎.
        let backend = AppSettings.asrBackend
        let localItem = NSMenuItem(title: "识别引擎：本地模型",
                                   action: #selector(useLocalASR), keyEquivalent: "")
        localItem.target = self
        localItem.state = backend == .local ? .on : .off
        menu.addItem(localItem)

        let remoteItem = NSMenuItem(title: "识别引擎：在线接口",
                                    action: #selector(useRemoteASR), keyEquivalent: "")
        remoteItem.target = self
        remoteItem.state = backend == .openAI ? .on : .off
        menu.addItem(remoteItem)

        menu.addItem(.separator())

        let dashItem = NSMenuItem(title: "仪表盘…", action: #selector(openDashboardFromMenu), keyEquivalent: "")
        dashItem.target = self
        menu.addItem(dashItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Sotto", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func openDashboardFromMenu() { showMainWindow() }

    // Backend is re-read per utterance, so flipping the config is all it takes;
    // refresh keeps the dashboard's ASR badge in sync if it's open.
    @objc private func useLocalASR() {
        AppSettings.asrBackend = .local
        speechEngine.applyBackendSelection()
        dashboardWindowVC.refresh()
    }

    @objc private func useRemoteASR() {
        AppSettings.asrBackend = .openAI
        speechEngine.applyBackendSelection()
        dashboardWindowVC.refresh()
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            if !keyMonitor.start() { showAccessibilityAlert() }
        } else {
            keyMonitor.stop()
            if recState != .idle {
                speechEngine.cancel()
                muteGuard.unmute()
                overlayPanel.dismiss()
                recState = .idle
                holdStart = nil
                updateStatusIcon(recording: false)
            }
        }
    }

    @objc private func openSettings() {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
            Sotto 需要「辅助功能」权限来监听快捷键。

            1. 打开 系统设置 → 隐私与安全性 → 辅助功能
            2. 添加并启用 Sotto
            3. 重启 App
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "退出")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
