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
    panel.show(text: "正在聆听…")
    var up = true
    var lvl: Float = 0.1
    Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
        panel.updateAudioLevel(lvl)
        if up { lvl += 0.08 } else { lvl -= 0.08 }
        if lvl >= 0.9 { up = false }
        if lvl <= 0.05 { up = true }
    }
    app.run()
}

// Debug-only: `--render-wave` bakes the waveform (at a fixed level) to a PNG
// for offscreen visual checks — no screen-recording permission needed.
if CommandLine.arguments.contains("--render-wave") {
    let v = WaveformView(frame: NSRect(x: 0, y: 0, width: 160, height: 64))
    v.wantsLayer = true
    let host = NSView(frame: v.bounds)
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
    host.addSubview(v)
    let win = NSWindow(contentRect: host.bounds, styleMask: .borderless,
                       backing: .buffered, defer: false)
    win.backgroundColor = NSColor(white: 0.07, alpha: 1)
    win.contentView = host
    win.makeKeyAndOrderFront(nil)
    v.isAnimating = true
    v.isListening = true
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in v.setLevel(0.65) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/sotto_wave.png"))
        }
        exit(0)
    }
    app.run()
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
