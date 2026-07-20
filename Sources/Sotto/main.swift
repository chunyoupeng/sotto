import AppKit

let app = NSApplication.shared
// `.regular`: Sotto is a real app — it owns a Dock icon and main window and is
// reachable via ⌘-Tab — while still keeping its menu-bar item. Maintenance/debug
// invocations below exit before the delegate, so the policy is harmless there.
app.setActivationPolicy(.regular)

// Maintenance-only: create/repair ~/.sotto without launching the menu-bar app.
if CommandLine.arguments.contains("--repair-sotto") {
    _ = SottoConfig.object("holdEnabled")
    print(SottoConfig.homeDir.path)
    exit(0)
}

// Debug-only: `--preview-overlay` renders the overlay in various states for
// visual verification, then idles so it can be screenshotted. Not built into
// normal runs (no entry point reachable from the shipped app).
if CommandLine.arguments.contains("--preview-overlay") {
    let panel = OverlayPanel()
    var up = true
    var lvl: Float = 0.1
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        panel.updateAudioLevel(lvl)
        if up { lvl += 0.05 } else { lvl -= 0.05 }
        if lvl >= 0.9 { up = false }
        if lvl <= 0.05 { up = true }
    }
    // Loop the full session choreography: listening wave → orb thinking →
    // merge + scale-out, so every phase can be eyeballed / screenshotted.
    var step = 0
    func advance() {
        switch step % 4 {
        case 0: panel.show(text: "正在聆听…")
        case 1: panel.showTranscribing()
        case 2: panel.showRefining()
        default: panel.showResult("你好，这是一次测试。"); panel.dismiss(after: 0.8)
        }
        step += 1
        let delay: TimeInterval = step % 4 == 0 ? 2.2 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { advance() }
    }
    advance()
    app.run()
}

// Debug-only: `--preview-ui` opens every surface (settings, dashboard, QA
// panel, overlay) at fixed positions and prints screencapture-ready regions
// ("REGION <name> <x> <y> <w> <h>", top-left origin), then idles for
// screenshots. Not reachable from normal runs.
if CommandLine.arguments.contains("--preview-ui") {
    setbuf(stdout, nil)  // REGION lines must reach a redirected pipe immediately
    app.setActivationPolicy(.accessory)
    let screen = NSScreen.main!
    let screenH = screen.frame.height

    func printRegion(_ name: String, _ f: NSRect) {
        let pad: CGFloat = 24
        let x = max(f.origin.x - pad, 0)
        let y = max(screenH - (f.origin.y + f.height) - pad, 0)
        print("REGION \(name) \(Int(x)) \(Int(y)) \(Int(f.width + pad * 2)) \(Int(f.height + pad * 2))")
    }

    let settings = SettingsWindow()
    settings.hidesOnDeactivate = false  // preview app is never "active"
    if let tab = ProcessInfo.processInfo.environment["SOTTO_PREVIEW_TAB"].flatMap(Int.init) {
        settings.selectTab(tab)
    }
    settings.setFrameOrigin(NSPoint(x: 60, y: screenH - 760 - 120))
    settings.orderFrontRegardless()
    printRegion("settings", settings.frame)

    let dashVC = DashboardViewController()
    let dashWin = NSWindow(contentViewController: dashVC)
    dashWin.styleMask = [.titled]
    dashWin.title = "Sotto"
    dashWin.appearance = NSAppearance(named: .darkAqua)
    dashVC.refresh()
    dashWin.setFrameOrigin(NSPoint(x: 760, y: screenH - 620 - 120))
    dashWin.orderFrontRegardless()
    printRegion("dashboard", dashWin.frame)

    let qa = QAPanel()
    qa.present(question: "苹果的流体界面设计核心原则是什么？",
               answer: "核心是四点：即时响应（按下瞬间就有反馈）、直接操纵（内容 1:1 跟随手势）、可中断（动画随时可以被抓住并反向）、以及动量传递（松手后动画继承手势的速度）。弹簧动画天然满足这些要求，因此成为默认工具。")
    qa.setFrameOrigin(NSPoint(x: 1240, y: screenH - 420 - 180))
    printRegion("qa", qa.frame)

    let editorRecord = DictationRecord(
        id: "preview", date: Date(), durationSeconds: 2.1,
        rawText: "因为出图后再改善都已重做了。",
        refinedText: "因为出图后再改善，都已经重做了。")
    RecordEditorWindowController.present(for: editorRecord) { _ in }
    if let editorWin = NSApp.windows.first(where: { $0 is NSPanel && $0.frame.width == 520 }) {
        editorWin.setFrameOrigin(NSPoint(x: 1240, y: screenH - 420 - 620))
        printRegion("editor", editorWin.frame)
    }

    let overlay = OverlayPanel()
    overlay.show(text: "正在聆听…")
    var up = true
    var lvl: Float = 0.1
    Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
        overlay.updateAudioLevel(lvl)
        if up { lvl += 0.08 } else { lvl -= 0.08 }
        if lvl >= 0.9 { up = false }
        if lvl <= 0.05 { up = true }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        printRegion("overlay", overlay.frame)
        print("READY")
    }
    app.run()
}


let delegate = AppDelegate()
app.delegate = delegate
app.run()
