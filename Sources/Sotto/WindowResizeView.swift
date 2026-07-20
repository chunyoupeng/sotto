import AppKit

/// Transparent edge hit target for full-size-content windows.
///
/// AppKit normally owns these regions, but a full-size content view containing
/// an overlay scroller can make the right edge feel like part of the page. This
/// view guarantees an 8 pt resize target, a visible resize cursor, and native-
/// feeling live resizing on all four edges and corners.
final class WindowResizeView: NSView {
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let bottom = Edges(rawValue: 1 << 2)
        static let top = Edges(rawValue: 1 << 3)
    }

    private let thickness: CGFloat = 8
    private var dragEdges: Edges = []
    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        edges(at: point).isEmpty ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: 0, width: thickness, height: bounds.height),
                      cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - thickness, y: 0,
                             width: thickness, height: bounds.height),
                      cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: thickness),
                      cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.height - thickness,
                             width: bounds.width, height: thickness),
                      cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragEdges = edges(at: convert(event.locationInWindow, from: nil))
        SottoLog.log("Resize", "down loc=\(NSStringFromPoint(event.locationInWindow)) " +
                     "bounds=\(NSStringFromRect(bounds)) frame=\(NSStringFromRect(frame)) " +
                     "edges=\(dragEdges.rawValue)")
        guard !dragEdges.isEmpty else { return }
        startMouse = NSEvent.mouseLocation
        startFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, !dragEdges.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        let minSize = window.minSize
        let maxSize = window.maxSize
        var frame = startFrame

        if dragEdges.contains(.left) {
            let width = clamp(startFrame.width - dx, min: minSize.width, max: maxSize.width)
            frame.origin.x = startFrame.maxX - width
            frame.size.width = width
        } else if dragEdges.contains(.right) {
            frame.size.width = clamp(startFrame.width + dx, min: minSize.width, max: maxSize.width)
        }

        if dragEdges.contains(.bottom) {
            let height = clamp(startFrame.height - dy, min: minSize.height, max: maxSize.height)
            frame.origin.y = startFrame.maxY - height
            frame.size.height = height
        } else if dragEdges.contains(.top) {
            frame.size.height = clamp(startFrame.height + dy, min: minSize.height, max: maxSize.height)
        }

        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        dragEdges = []
    }

    private func edges(at point: NSPoint) -> Edges {
        guard bounds.insetBy(dx: -1, dy: -1).contains(point) else { return [] }
        var result: Edges = []
        if point.x <= thickness { result.insert(.left) }
        if point.x >= bounds.width - thickness { result.insert(.right) }
        if point.y <= thickness { result.insert(.bottom) }
        if point.y >= bounds.height - thickness { result.insert(.top) }
        return result
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
