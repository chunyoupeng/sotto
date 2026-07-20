import AppKit
import QuartzCore

/// Shared visual language for Sotto's surfaces.
///
/// Everything reads as one app: a dark-glass vibrancy base with a
/// cyan → indigo → violet accent gradient. Used by the overlay panel, the
/// dashboard, and the settings window so their look stays consistent.
///
/// The material hierarchy follows Apple's guidance: the window is dark glass,
/// *raised* (lighter) surfaces draw attention to content and controls, and
/// *recessed* (darker) wells hold editors and inputs. Motion is spring-based
/// and interruptible — animations start from the presentation value.
enum SottoTheme {
    // MARK: - Workspace palette

    /// OpenLess-inspired workspace surfaces: quiet zinc layers with one blue
    /// accent. The floating recorder keeps its more expressive state colors.
    static let workspaceBackground = NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.078, alpha: 1)
    static let workspaceSurface = NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.118, alpha: 1)
    static let workspaceWell = NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.065, alpha: 1)
    static let workspaceLine = NSColor(calibratedRed: 0.153, green: 0.153, blue: 0.169, alpha: 1)
    static let workspaceAccent = NSColor(calibratedRed: 0.455, green: 0.718, blue: 1.0, alpha: 1)
    static let workspacePrimaryText = NSColor(calibratedWhite: 0.98, alpha: 1)
    static let workspaceSecondaryText = NSColor(calibratedWhite: 0.67, alpha: 1)
    /// Signature accent stops: cyan → indigo → violet (no rainbow cycling).
    static let palette: [CGColor] = [
        CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),  // cyan
        CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1),  // indigo
        CGColor(red: 0.66, green: 0.33, blue: 0.95, alpha: 1),  // violet
    ]

    /// Indigo accent (the middle stop) — solid accent fills/glows.
    static let accent = CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1)

    /// Per-state accent palettes for the waveform. Index 0 is the dominant tint.
    enum State {
        static let listening: [CGColor] = [
            CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),  // cyan
            CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1),  // indigo
        ]
        /// Translate-mode listening: green, so the mode is obvious at a glance.
        static let listeningTranslate: [CGColor] = [
            CGColor(red: 0.25, green: 0.87, blue: 0.45, alpha: 1),  // green
            CGColor(red: 0.10, green: 0.65, blue: 0.55, alpha: 1),  // teal
        ]
        /// QA-mode listening: pink/magenta, distinct from both others.
        static let listeningQA: [CGColor] = [
            CGColor(red: 0.96, green: 0.42, blue: 0.62, alpha: 1),  // pink
            CGColor(red: 0.78, green: 0.30, blue: 0.88, alpha: 1),  // magenta
        ]
        static let transcribing: [CGColor] = [
            CGColor(red: 0.95, green: 0.74, blue: 0.31, alpha: 1),  // amber
            CGColor(red: 0.95, green: 0.55, blue: 0.34, alpha: 1),  // warm
        ]
        static let refining: [CGColor] = [
            CGColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),  // violet
            CGColor(red: 0.66, green: 0.33, blue: 0.95, alpha: 1),  // deep violet
        ]
        static let result: [CGColor] = [
            CGColor(red: 0.30, green: 0.92, blue: 0.68, alpha: 1),  // mint
            CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),  // cyan
        ]
        /// Nothing to do — no speech heard, or filler-only content. Deliberately
        /// muted/gray so it doesn't read as an active state or a success.
        static let cancelled: [CGColor] = [
            CGColor(red: 0.58, green: 0.60, blue: 0.66, alpha: 1),  // muted gray
            CGColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1),  // deeper gray
        ]
    }

    /// A gradient layer painted with `palette`, horizontal by default.
    static func gradientLayer(frame: CGRect = .zero,
                              colors: [CGColor] = palette,
                              start: CGPoint = CGPoint(x: 0, y: 0.5),
                              end: CGPoint = CGPoint(x: 1, y: 0.5)) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.colors = colors
        g.startPoint = start
        g.endPoint = end
        g.frame = frame
        return g
    }

    /// A configured dark-glass vibrancy view (the surface every window sits on).
    static func makeVibrancyContainer(frame: CGRect = .zero,
                                       material: NSVisualEffectView.Material = .hudWindow,
                                       cornerRadius: CGFloat = 0) -> NSVisualEffectView {
        let v = NSVisualEffectView(frame: frame)
        v.autoresizingMask = [.width, .height]
        v.material = material
        v.state = .active
        v.wantsLayer = true
        v.appearance = NSAppearance(named: .darkAqua)
        if cornerRadius > 0 {
            v.layer?.cornerRadius = cornerRadius
            v.layer?.masksToBounds = true
        }
        return v
    }

    /// Lay a dark-glass background under an existing content view and force a
    /// dark appearance so native controls (tab views, buttons, text fields)
    /// render in dark mode to match. Existing subviews stay on top.
    static func applyDarkGlass(to window: NSWindow,
                               material: NSVisualEffectView.Material = .hudWindow) {
        guard let cv = window.contentView else { return }
        cv.wantsLayer = true
        let effect = makeVibrancyContainer(frame: cv.bounds, material: material)
        cv.addSubview(effect, positioned: .below, relativeTo: nil)
        window.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Surfaces (material hierarchy)

    static let cardCornerRadius: CGFloat = 12

    /// Raised surface — a lighter layer on the dark glass that lifts content
    /// toward the user (stat cards, history rows, the answer card). The bright
    /// top border reads as light catching the material's edge.
    static func styleAsCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cardCornerRadius
        view.layer?.backgroundColor = workspaceSurface.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = workspaceLine.cgColor
    }

    /// Recessed surface — a darker well the user pours content *into*
    /// (prompt/hotword editors, path fields' host, tab content).
    static func styleAsWell(_ view: NSView, cornerRadius: CGFloat = 10) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.backgroundColor = workspaceWell.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = workspaceLine.cgColor
    }

    // Kept for callers that want the raw values.
    static let cardBorderColor = workspaceLine.cgColor
    static let cardBorderWidth: CGFloat = 1
    static let cardBackground = workspaceSurface

    /// Label colors tuned for the dark glass surface (vibrancy-friendly:
    /// slightly brighter + heavier than plain gray so text stays legible
    /// over the translucent material).
    static let secondaryLabelColor = workspaceSecondaryText
    static let primaryLabelColor = workspacePrimaryText
    static let tertiaryLabelColor = NSColor(calibratedWhite: 0.46, alpha: 1)

    // MARK: - Typography

    /// Large display text: negative tracking that scales with size — big type
    /// reads too loose at default spacing. Body sizes stay near zero.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        size >= 20 ? size * -0.02 : (size >= 15 ? size * -0.01 : 0)
    }

    /// A display/title label with size-appropriate negative tracking.
    static func displayLabel(_ text: String, size: CGFloat,
                             weight: NSFont.Weight = .semibold,
                             color: NSColor = primaryLabelColor) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: tracking(forSize: size),
        ])
        return l
    }

    /// A small, slightly letterspaced caption used as a section header.
    /// The positive tracking keeps tiny text legible (small type wants air).
    static func captionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: secondaryLabelColor,
            .kern: 0.4,
        ])
        return l
    }

    // MARK: - Motion

    /// A critically-damped (or slightly bouncy) spring in Apple's
    /// damping-ratio + response parameterization. Interruptible by design:
    /// callers should read the presentation layer for `fromValue` so a
    /// re-target starts from the current on-screen value.
    static func spring(keyPath: String,
                       response: CGFloat = 0.35,
                       dampingRatio: CGFloat = 1.0) -> CASpringAnimation {
        let a = CASpringAnimation(keyPath: keyPath)
        a.mass = 1
        let stiffness = pow(2 * Double.pi / Double(response), 2)
        a.stiffness = CGFloat(stiffness)
        a.damping = CGFloat(2 * Double(dampingRatio) * stiffness.squareRoot())
        a.duration = a.settlingDuration
        return a
    }
}

// MARK: - Pill button

/// A capsule button with instant press feedback (scale on mouse-*down*, not on
/// release), a gentle hover brighten, and a spring release. `primary` uses
/// the workspace's solid blue accent; `neutral` is a translucent chip; `destructive`
/// is a neutral chip with a red label.
final class PillButton: NSButton {
    enum Style { case primary, neutral, destructive }
    enum Size { case regular, small }

    private let style: Style
    private let sizeClass: Size
    private let hoverTint = CALayer()

    init(title: String, style: Style = .neutral, size: Size = .regular,
         target: AnyObject? = nil, action: Selector? = nil) {
        self.style = style
        self.sizeClass = size
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)

        let fontSize: CGFloat = size == .regular ? 13 : 11.5
        let color: NSColor
        switch style {
        case .primary: color = .white
        case .neutral: color = SottoTheme.primaryLabelColor
        case .destructive: color = NSColor.systemRed.withAlphaComponent(0.9)
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: style == .primary ? .semibold : .medium),
            .foregroundColor: color,
        ])

        layer?.masksToBounds = true
        switch style {
        case .primary:
            layer?.backgroundColor = SottoTheme.workspaceAccent.cgColor
        case .neutral, .destructive:
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        }
        // Hover brighten: a white veil whose opacity animates in/out.
        hoverTint.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        hoverTint.opacity = 0
        layer?.addSublayer(hoverTint)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        let h: CGFloat = sizeClass == .regular ? 30 : 24
        let padH: CGFloat = sizeClass == .regular ? 30 : 20
        return NSSize(width: s.width + padH, height: h)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverTint.frame = bounds
        CATransaction.commit()
        // Never touch anchorPoint/position here: AppKit owns a layer-backed
        // view's layer geometry, and repositioning by `bounds` (self-relative)
        // instead of `frame` (superlayer-relative) piled sibling buttons onto
        // one spot. Centered press-scale is built into the transform instead.
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    private func setHover(_ on: Bool) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = hoverTint.presentation()?.opacity ?? hoverTint.opacity
        a.toValue = on ? 0.6 : 0
        a.duration = on ? 0.10 : 0.22  // instant in, relaxed out
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        hoverTint.opacity = on ? 0.6 : 0
        hoverTint.add(a, forKey: "hover")
    }

    /// Feedback lives on the press: scale down the instant the mouse goes
    /// down; spring back after `super.mouseDown` returns (it blocks until
    /// mouse-up and fires the action).
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        scale(to: 0.96, response: 0.12)
        super.mouseDown(with: event)
        scale(to: 1.0, response: 0.30)
    }

    /// Scale around the button's center with the default (0,0) anchor by
    /// sandwiching the scale between translations.
    private func scale(to value: CGFloat, response: CGFloat) {
        guard let l = layer else { return }
        var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        t = CATransform3DScale(t, value, value, 1)
        t = CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
        let a = SottoTheme.spring(keyPath: "transform", response: response)
        a.fromValue = (l.presentation() ?? l).value(forKeyPath: "transform")
        a.toValue = t
        l.transform = t
        l.add(a, forKey: "press")
    }
}

// MARK: - Sliding tab bar

/// A segmented tab bar whose selection is a capsule that *slides* between
/// segments on a spring. Interruptible: rapid clicks re-target the spring from
/// the indicator's current on-screen position, so it never jumps or queues.
final class SlidingTabBar: NSView {
    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private let indicator = NSView()
    private var buttons: [NSButton] = []
    private let titles: [String]

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        wantsLayer = true
        SottoTheme.styleAsWell(self, cornerRadius: 16)

        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        indicator.layer?.borderWidth = 0.5
        indicator.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(indicator)

        for (i, t) in titles.enumerated() {
            let b = NSButton(title: t, target: self, action: #selector(tabClicked(_:)))
            b.isBordered = false
            b.tag = i
            b.setButtonType(.momentaryChange)
            addSubview(b)
            buttons.append(b)
        }
        restyleTitles()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }

    private func restyleTitles() {
        for (i, b) in buttons.enumerated() {
            let selected = i == selectedIndex
            b.attributedTitle = NSAttributedString(string: titles[i], attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium),
                .foregroundColor: selected ? SottoTheme.primaryLabelColor
                                           : SottoTheme.secondaryLabelColor,
            ])
        }
    }

    private func segmentFrame(_ i: Int) -> NSRect {
        let n = CGFloat(max(buttons.count, 1))
        let w = bounds.width / n
        return NSRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        indicator.layer?.cornerRadius = (bounds.height - 6) / 2
        for (i, b) in buttons.enumerated() { b.frame = segmentFrame(i) }
        indicator.frame = segmentFrame(selectedIndex).insetBy(dx: 3, dy: 3)
    }

    @objc private func tabClicked(_ sender: NSButton) {
        select(sender.tag)
    }

    func select(_ index: Int, animated: Bool = true) {
        guard index != selectedIndex, index >= 0, index < buttons.count else { return }
        selectedIndex = index
        restyleTitles()
        let target = segmentFrame(index).insetBy(dx: 3, dy: 3)
        if animated, let l = indicator.layer {
            // Spring from the *presentation* position so a click mid-flight
            // redirects the capsule instead of restarting it.
            let a = SottoTheme.spring(keyPath: "position.x", response: 0.35)
            a.fromValue = (l.presentation() ?? l).position.x
            indicator.frame = target
            a.toValue = l.position.x
            l.add(a, forKey: "slide")
        } else {
            indicator.frame = target
        }
        onSelect?(index)
    }
}
