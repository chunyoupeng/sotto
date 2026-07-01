import AppKit
import QuartzCore

/// Shared visual language for Sotto's surfaces.
///
/// Everything reads as one app: a dark-glass vibrancy base with a
/// cyan → indigo → violet accent gradient. Used by the overlay panel, the
/// dashboard, and the settings window so their look stays consistent.
enum SottoTheme {
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

    // MARK: - Card chrome (dashboard rows / settings groups)

    static let cardCornerRadius: CGFloat = 8
    static let cardBorderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    static let cardBorderWidth: CGFloat = 0.5
    static let cardBackground = NSColor.black.withAlphaComponent(0.22)

    /// Style a plain NSView as a translucent rounded card.
    static func styleAsCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cardCornerRadius
        view.layer?.backgroundColor = cardBackground.cgColor
        view.layer?.borderWidth = cardBorderWidth
        view.layer?.borderColor = cardBorderColor
    }

    /// Secondary label color tuned for the dark glass surface.
    static let secondaryLabelColor = NSColor.white.withAlphaComponent(0.55)
    static let primaryLabelColor = NSColor.white.withAlphaComponent(0.92)
}
