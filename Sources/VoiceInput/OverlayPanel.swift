import AppKit
import QuartzCore

final class OverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let waveformView = WaveformView()

    private let capsuleHeight: CGFloat = 60
    private let hPad: CGFloat = 26
    private let waveSize: CGFloat = 104   // wave is the centerpiece, not a corner accent
    private let gap: CGFloat = 12
    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 560

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

        // Soft outer shadow.
        let shadowHost = NSView(frame: cv.bounds)
        shadowHost.autoresizingMask = [.width, .height]
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -3)
        shadowHost.layer?.shadowRadius = 22
        shadowHost.layer?.shadowOpacity = 1
        cv.addSubview(shadowHost)

        // Vibrancy capsule (dark glass).
        let effect = SottoTheme.makeVibrancyContainer(
            frame: cv.bounds, cornerRadius: capsuleHeight / 2)
        shadowHost.addSubview(effect)

        // Inner hairline border.
        let border = NSView(frame: cv.bounds)
        border.autoresizingMask = [.width, .height]
        border.wantsLayer = true
        border.layer?.cornerRadius = capsuleHeight / 2
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        effect.addSubview(border)

        // Top glass highlight: a thin vertical sheen along the capsule's top
        // edge for depth (the "lit edge" of a glass pill).
        let sheen = CAGradientLayer()
        sheen.colors = [
            NSColor.white.withAlphaComponent(0.20).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        sheen.startPoint = CGPoint(x: 0.5, y: 0)
        sheen.endPoint = CGPoint(x: 0.5, y: 1)
        sheen.frame = CGRect(x: 0, y: cv.bounds.height - 14, width: cv.bounds.width, height: 14)
        sheen.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        effect.layer?.addSublayer(sheen)

        // Layout: waveform + live caption.
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = gap
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(waveformView)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = SottoTheme.primaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: hPad),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -hPad),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
    }

    // MARK: - Public

    func show(text: String = "正在聆听…") {
        label.stringValue = text
        waveformView.state = .listening
        waveformView.isListening = true
        waveformView.isAnimating = true

        let w = idealWidth(for: text)
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = area.midX - w / 2
        let y = area.minY + 56

        setFrame(NSRect(x: x, y: y - 14, width: w, height: capsuleHeight), display: true)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            animator().alphaValue = 1
            animator().setFrame(
                NSRect(x: x, y: y, width: w, height: capsuleHeight), display: true)
        }
    }

    /// Generic text update that preserves the current wave state (used when the
    /// caption changes within the same state, e.g. tap-to-lock keeping the listening status.
    func updateText(_ text: String) {
        label.stringValue = text
        relayout()
    }

    func showTranscribing() {
        waveformView.state = .transcribing
        waveformView.isListening = false
        updateText("转写中…")
    }

    func showRefining() {
        waveformView.state = .refining
        waveformView.isListening = false
        updateText("润色中…")
    }

    func showResult(_ text: String) {
        waveformView.state = .result
        waveformView.isListening = false
        updateText(text)
    }

    func updateAudioLevel(_ level: Float) {
        waveformView.setLevel(CGFloat(level))
    }

    func dismiss() {
        waveformView.isAnimating = false
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
            self.orderOut(nil)
        })
    }

    // MARK: - Sizing

    private func relayout() {
        let w = idealWidth(for: label.stringValue)
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = area.midX - w / 2
        let newFrame = NSRect(x: x, y: frame.origin.y, width: w, height: capsuleHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            ctx.allowsImplicitAnimation = true
            animator().setFrame(newFrame, display: true)
        }
    }

    private func idealWidth(for text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font!]
        let textW = ceil((text as NSString).size(withAttributes: attrs).width)
        let total = hPad + waveSize + gap + textW + hPad
        return min(max(total, minWidth), maxWidth)
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
    enum State { case listening, transcribing, refining, result }

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
        case .listening:    colors = SottoTheme.State.listening
        case .transcribing:  colors = SottoTheme.State.transcribing
        case .refining:      colors = SottoTheme.State.refining
        case .result:        colors = SottoTheme.State.result
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
