import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let speechEngine = SpeechEngine()
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true

    // Recording state machine.
    private enum RecState { case idle, holding, locked }
    private var recState: RecState = .idle
    private var holdStart: Date?

    private lazy var settingsWindow = SettingsWindow()
    private let dashboardPopover = NSPopover()
    private lazy var dashboardVC = DashboardViewController()
    // Separate instance for the standalone window (a VC's view can't be in two
    // places at once); used by the global hotkey so it works even when the
    // menu-bar icon is hidden behind the notch.
    private lazy var dashboardWindowVC = DashboardViewController()
    private var dashboardWindow: NSWindow?

    private var selectedLocaleCode: String { AppSettings.localeCode }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let code = selectedLocaleCode
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)

        // Touch the store eagerly so its one-time data-dir migration
        // (VoiceInput → Sotto) runs at launch rather than on first dashboard open.
        _ = RecordStore.shared

        setupMainMenu()
        setupStatusBar()
        setupSpeechCallbacks()
        setupDashboard()
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
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)
    }

    // MARK: - Trigger handling

    private func handleHoldDown() {
        guard isEnabled else { return }
        switch recState {
        case .idle: startCapture(locked: false)
        case .locked: stopAndFinish()   // pressing the hold key again ends a locked session
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

    // MARK: - Capture lifecycle

    private func startCapture(locked: Bool) {
        guard isEnabled, recState == .idle else { return }
        LLMRefiner.shared.cancel()
        recState = locked ? .locked : .holding
        holdStart = Date()
        updateStatusIcon(recording: true)
        overlayPanel.show(text: "正在聆听…")
        NSSound(named: .init("Tink"))?.play()
        speechEngine.startRecording()
    }

    private func stopAndFinish() {
        guard recState != .idle else { return }
        recState = .idle
        holdStart = nil
        updateStatusIcon(recording: false)
        speechEngine.stopRecording()   // → onFinalResultFull
        overlayPanel.showTranscribing()
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechEngine.onFinalResultFull = { [weak self] raw, audioURL, duration in
            self?.handleFinal(raw: raw, audioURL: audioURL, duration: duration)
        }

        speechEngine.onError = { [weak self] msg in
            guard let self else { return }
            self.recState = .idle
            self.overlayPanel.updateText("出错：\(msg)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.overlayPanel.dismiss()
            }
        }

        speechEngine.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }
    }

    private func handleFinal(raw: String, audioURL: URL?, duration: TimeInterval) {
        let rawText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            if let u = audioURL { try? FileManager.default.removeItem(at: u) }
            dismissWithNotice("未听到任何声音")
            return
        }

        let refiner = LLMRefiner.shared
        if refiner.isEnabled && refiner.isConfigured {
            overlayPanel.showRefining()
            refiner.refine(rawText) { [weak self] result in
                guard let self else { return }
                let refined: String
                switch result {
                case .success(let r): refined = r.isEmpty ? rawText : r
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
            RecordStore.shared.add(rawText: raw, refinedText: refined,
                                   duration: duration, tempAudioURL: audioURL)
        }
        if let u = audioURL { try? FileManager.default.removeItem(at: u) }

        overlayPanel.showResult(refined)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.overlayPanel.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.textInjector.inject(refined)
                NSSound(named: .init("Pop"))?.play()
            }
        }

        if dashboardPopover.isShown { dashboardVC.refresh() }
        if let win = dashboardWindow, win.isVisible { dashboardWindowVC.refresh() }
    }

    /// Briefly flash a non-error notice in the overlay (no speech heard, or the
    /// utterance was filler-only) instead of vanishing silently, then dismiss —
    /// so "nothing to type" still reads as "Sotto heard you," not "Sotto froze."
    private func dismissWithNotice(_ text: String) {
        overlayPanel.showCancelled(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.overlayPanel.dismiss()
        }
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

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleDashboard()
        }
    }

    // MARK: - Dashboard

    private func setupDashboard() {
        dashboardVC.onOpenSettings = { [weak self] in
            self?.dashboardPopover.performClose(nil)
            self?.openSettings()
        }
        dashboardPopover.contentViewController = dashboardVC
        dashboardPopover.behavior = .transient
        dashboardPopover.appearance = NSAppearance(named: .darkAqua)
    }

    private func toggleDashboard() {
        if dashboardPopover.isShown {
            dashboardPopover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        dashboardVC.refresh()
        NSApp.activate(ignoringOtherApps: true)
        dashboardPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// The real, ⌘-Tab-switchable main window. Created lazily and reused.
    private func mainWindowIfNeeded() -> NSWindow {
        if let existing = dashboardWindow { return existing }
        dashboardWindowVC.onOpenSettings = { [weak self] in self?.openSettings() }
        let win = NSWindow(contentViewController: dashboardWindowVC)
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = "Sotto"
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)
        win.center()
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

    @objc private func openDashboardFromMenu() { toggleDashboard() }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            if !keyMonitor.start() { showAccessibilityAlert() }
        } else {
            keyMonitor.stop()
            if recState != .idle {
                speechEngine.cancel()
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
