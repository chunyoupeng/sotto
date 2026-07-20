import AppKit
import QuartzCore

final class OverlayPanel: NSPanel {
    private let waveformView = WaveformView()

    private let capsuleWidth: CGFloat = 200
    private let capsuleHeight: CGFloat = 60
    private let waveSize: CGFloat = 104   // wave is the centerpiece, not a corner accent

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let cv = contentView!
        cv.wantsLayer = true
        let radius = capsuleHeight / 2

        // Soft outer shadow so the capsule floats over any background.
        let shadowHost = NSView(frame: cv.bounds)
        shadowHost.autoresizingMask = [.width, .height]
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -3)
        shadowHost.layer?.shadowRadius = 18
        shadowHost.layer?.shadowOpacity = 1
        cv.addSubview(shadowHost)

        // The previous glass capsule, now reduced to its visual core: the live
        // waveform is centered and no status caption is rendered.
        let content = NSView(frame: cv.bounds)
        content.autoresizingMask = [.width, .height]

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(waveformView)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 44),
            waveformView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        if #available(macOS 26.0, *) {
            // Native Liquid Glass: the `.clear` style reads far more translucent
            // than stacked vibrancy, and there's no manual top sheen (which looked
            // like an odd bright bar). A faint dark tint keeps the caption legible.
            let glass = NSGlassEffectView(frame: cv.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .clear
            glass.cornerRadius = radius
            glass.tintColor = NSColor.black.withAlphaComponent(0.16)
            glass.contentView = content
            shadowHost.addSubview(glass)
        } else {
            // Fallback for older macOS: dark vibrancy capsule + hairline border.
            let effect = SottoTheme.makeVibrancyContainer(frame: cv.bounds, cornerRadius: radius)
            shadowHost.addSubview(effect)

            let border = NSView(frame: cv.bounds)
            border.autoresizingMask = [.width, .height]
            border.wantsLayer = true
            border.layer?.cornerRadius = radius
            border.layer?.borderWidth = 0.5
            border.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            effect.addSubview(border)

            effect.addSubview(content)
        }
    }

    // MARK: - Public

    enum CaptureStyle { case dictation, translate, qa }

    /// Keep the old waveform while preserving the newer mode-specific colors.
    func setCaptureStyle(_ style: CaptureStyle) {
        switch style {
        case .dictation: waveformView.listeningPalette = SottoTheme.State.listening
        case .translate: waveformView.listeningPalette = SottoTheme.State.listeningTranslate
        case .qa: waveformView.listeningPalette = SottoTheme.State.listeningQA
        }
    }

    /// Bumped on every `show()`. Delayed dismissals capture the value they were
    /// scheduled under and bail if a new session has taken over the panel since —
    /// otherwise a stale timer would hide the next session's listening UI.
    private var generation = 0

    func show(text: String = "") {
        generation += 1
        waveformView.state = .listening
        waveformView.isListening = true
        waveformView.isAnimating = true

        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = area.midX - capsuleWidth / 2
        let y = area.minY + 56

        setFrame(NSRect(x: x, y: y - 14, width: capsuleWidth, height: capsuleHeight), display: true)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            animator().alphaValue = 1
            animator().setFrame(
                NSRect(x: x, y: y, width: capsuleWidth, height: capsuleHeight), display: true)
        }
    }

    /// Kept for call-site compatibility; the restored overlay is text-free.
    func updateText(_ text: String) {}

    func showTranscribing() {
        waveformView.state = .transcribing
        waveformView.isListening = false
    }

    func showRefining(_ text: String = "") {
        waveformView.state = .refining
        waveformView.isListening = false
    }

    func showResult(_ text: String) {
        waveformView.state = .result
        waveformView.isListening = false
    }

    func showError(_ text: String) {
        waveformView.state = .cancelled
        waveformView.isListening = false
    }

    /// Brief, non-error notice — no speech heard, or the content was filler-only.
    /// Caller is responsible for dismissing after a short delay.
    func showCancelled(_ text: String) {
        waveformView.state = .cancelled
        waveformView.isListening = false
    }

    func updateAudioLevel(_ level: Float) {
        waveformView.setLevel(CGFloat(level))
    }

    func dismiss() {
        waveformView.isAnimating = false
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(
                NSRect(
                    x: frame.origin.x + frame.width * 0.02,
                    y: frame.origin.y - 8,
                    width: frame.width * 0.96,
                    height: capsuleHeight),
                display: true)
        }, completionHandler: {
            // A show() during the fade means a new session owns the panel now.
            if gen == self.generation { self.orderOut(nil) }
        })
    }

    /// Dismiss after `delay`, unless a new session has shown the panel since.
    func dismiss(after delay: TimeInterval) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.dismiss()
        }
    }

}

// MARK: - Continuous audio waveform

/// A mirrored, audio-reactive waveform rendered as a gradient-filled spindle —
/// reads as a "voice / sound wave" rather than a bar meter. The upper and lower
/// halves mirror each other across the centerline and taper to zero at both
/// ends so it reads as a localized voice pulse. While listening it tracks the
/// mic level; while transcribing/refining it breathes gently; the accent
/// gradient shifts color per state (cyan → amber → violet → mint).
final class WaveformView: NSView {
    enum State { case listening, transcribing, refining, result, cancelled }

    /// Whether the wave should be live (panel visible). Stops the display link when false.
    var isAnimating = false {
        didSet {
            if isAnimating { startWave() } else { stopWave() }
        }
    }
    /// Whether to react to incoming audio levels. False during refining/result.
    var isListening = false {
        didSet { if !isListening { level = 0 } }
    }
    var state: State = .listening {
        didSet { applyStateColors() }
    }

    /// Accent used while `state == .listening` — swapped per capture mode
    /// (dictation / translate / QA) so each mode reads as its own color.
    var listeningPalette: [CGColor] = SottoTheme.State.listening {
        didSet { if state == .listening { applyStateColors() } }
    }

    private let grad = CAGradientLayer()        // gradient, masked to the fill
    private let shape = CAShapeLayer()          // crisp fill (the mask)
    private let midGlow = CAShapeLayer()        // medium halo
    private let wideGlow = CAShapeLayer()       // broad halo
    private let aura = CAGradientLayer()        // radial accent glow behind

    private var timer: Timer?
    private var phase: CGFloat = 0
    private var t: CGFloat = 0
    private var level: CGFloat = 0
    private var smoothed: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    private func setupLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        aura.type = .radial
        aura.startPoint = CGPoint(x: 0.5, y: 0.5)
        aura.endPoint = CGPoint(x: 1.0, y: 1.0)
        root.addSublayer(aura)

        for s in [wideGlow, midGlow] {
            s.fillColor = nil
            s.lineJoin = .round
            s.lineCap = .round
            root.addSublayer(s)
        }
        wideGlow.lineWidth = 7
        midGlow.lineWidth = 4

        shape.fillColor = NSColor.white.cgColor  // opaque → mask alpha
        shape.strokeColor = nil
        shape.lineJoin = .round
        shape.lineCap = .round

        grad.startPoint = CGPoint(x: 0, y: 0.5)
        grad.endPoint = CGPoint(x: 1, y: 0.5)
        grad.mask = shape
        root.addSublayer(grad)

        applyStateColors()
    }

    /// Recolor the gradient + glow tints for the current state.
    private func applyStateColors() {
        let colors: [CGColor]
        switch state {
        case .listening:    colors = listeningPalette
        case .transcribing:  colors = SottoTheme.State.transcribing
        case .refining:      colors = SottoTheme.State.refining
        case .result:        colors = SottoTheme.State.result
        case .cancelled:     colors = SottoTheme.State.cancelled
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grad.colors = colors
        let dom = colors[0]
        wideGlow.strokeColor = Self.fade(dom, 0.16)
        midGlow.strokeColor = Self.fade(dom, 0.28)
        aura.colors = [Self.fade(dom, 0.20), Self.fade(dom, 0)]
        CATransaction.commit()
    }

    private static func fade(_ c: CGColor, _ a: CGFloat) -> CGColor {
        (NSColor(cgColor: c) ?? .white).withAlphaComponent(a).cgColor
    }

    override func layout() {
        super.layout()
        let b = bounds
        aura.frame = b
        grad.frame = b
        shape.frame = b
        wideGlow.frame = b
        midGlow.frame = b
        redraw(amplitude: isAnimating ? max(smoothed, 0.08) : 0)
    }

    func setLevel(_ lvl: CGFloat) {
        guard isListening else { return }
        level = max(0, min(1, lvl))
    }

    // MARK: - Animation loop

    private func startWave() {
        guard timer == nil else { return }
        redraw(amplitude: max(smoothed, 0.08))
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopWave() {
        timer?.invalidate()
        timer = nil
        // Settle to a calm flat line so a frozen spike isn't left on screen.
        smoothed = 0
        redraw(amplitude: 0)
    }

    private func tick() {
        phase += 0.16
        t += 1

        let target = isListening ? level : 0
        let k: CGFloat = target > smoothed ? 0.35 : 0.12
        smoothed += (target - smoothed) * k
        if !isListening { level = 0 }

        // Gentle idle floor so the wave always has a pulse, even when silent.
        let breath = 0.07 + 0.035 * _sin(t * 0.06)
        let amp = max(smoothed, breath)
        redraw(amplitude: amp)
    }

    private func redraw(amplitude amp: CGFloat) {
        let path = wavePath(amplitude: amp)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        wideGlow.path = path
        midGlow.path = path
        CATransaction.commit()
    }

    /// A mirrored, edge-tapered spindle: the upper edge is a detuned-sine wave
    /// from left to right, the lower edge mirrors it back across the centerline,
    /// and `sin(u·π)` envelopes both ends to zero so it reads as a localized
    /// voice pulse rather than touching the edges.
    private func wavePath(amplitude amp: CGFloat) -> CGPath {
        let w = bounds.width, h = bounds.height
        guard w > 1, h > 1 else { return CGMutablePath() }
        let mid = h / 2
        let maxA = (h / 2) * 0.82
        let n = 46
        // Sample the wave once; the lower edge mirrors these exact values.
        var ys: [CGFloat] = []
        ys.reserveCapacity(n + 1)
        for i in 0...n {
            let u = CGFloat(i) / CGFloat(n)
            let env = _sin(u * .pi)                      // 0 at edges → 1 mid
            let f1 = _sin(phase + u * 8.5)
            let f2 = _sin(phase * 1.3 + u * 15.0 + 1.1)
            let detail = _sin(phase * 0.7 + u * 29.0 + 0.4)
            ys.append(maxA * env * amp * (0.58 * f1 + 0.34 * f2 + 0.08 * detail))
        }
        let path = CGMutablePath()
        // Upper edge: left → right (above the midline).
        for i in 0...n {
            let x = CGFloat(i) / CGFloat(n) * w
            let p = CGPoint(x: x, y: mid - ys[i])
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // Lower edge: right → left, mirrored below the midline, then close.
        for i in stride(from: n, through: 0, by: -1) {
            let x = CGFloat(i) / CGFloat(n) * w
            path.addLine(to: CGPoint(x: x, y: mid + ys[i]))
        }
        path.closeSubpath()
        return path
    }
}

/// `sin` for `CGFloat` (CoreGraphics' overload isn't reliably visible here).
private func _sin(_ x: CGFloat) -> CGFloat { CGFloat(sin(Double(x))) }
