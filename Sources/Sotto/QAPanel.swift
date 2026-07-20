import AppKit

/// Floating chat panel for the QA hotkey. A simple chatbot transcript: each
/// spoken question and its answer append as bubbles, and the whole history of
/// the current session can be scrolled. Styled to match the main workspace
/// (solid zinc surfaces, one blue accent) instead of HUD glass.
/// Non-activating so the frontmost app keeps focus; Esc or ✕ dismisses.
final class QAPanel: NSPanel {

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    /// One transcript entry: a user question (right, accent tint) or an answer
    /// (left, raised card with a copy button).
    private final class ChatBubble: NSView {
        private let text: String

        init(text: String, isUser: Bool) {
            self.text = text
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 12
            if isUser {
                layer?.backgroundColor = SottoTheme.workspaceAccent.withAlphaComponent(0.16).cgColor
                layer?.borderWidth = 1
                layer?.borderColor = SottoTheme.workspaceAccent.withAlphaComponent(0.28).cgColor
            } else {
                layer?.backgroundColor = SottoTheme.workspaceSurface.cgColor
                layer?.borderWidth = 1
                layer?.borderColor = SottoTheme.workspaceLine.cgColor
            }

            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.textColor = SottoTheme.primaryLabelColor
            label.isSelectable = true
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)

            var constraints = [
                label.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            ]
            if isUser {
                constraints.append(label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12))
            } else {
                // Answers get a copy button in the top-right corner.
                let copy = NSButton()
                copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")?
                    .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
                copy.isBordered = false
                copy.contentTintColor = SottoTheme.secondaryLabelColor
                copy.target = self
                copy.action = #selector(copyText)
                copy.translatesAutoresizingMaskIntoConstraints = false
                addSubview(copy)
                constraints += [
                    copy.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                    copy.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: copy.leadingAnchor, constant: -8),
                    trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
                ]
            }
            NSLayoutConstraint.activate(constraints)
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func copyText() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private let scrollView = NSScrollView()
    private let transcript = NSStackView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        setupUI()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    // MARK: - UI

    private func setupUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = SottoTheme.workspaceBackground.cgColor
        cv.layer?.cornerRadius = 16
        cv.layer?.borderWidth = 1
        cv.layer?.borderColor = SottoTheme.workspaceLine.cgColor
        cv.layer?.masksToBounds = true
        appearance = NSAppearance(named: .darkAqua)

        // --- Header: title centered, close button on the right ---
        let titleLabel = SottoTheme.displayLabel("Sotto · 问答", size: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton()
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        closeButton.isBordered = false
        closeButton.contentTintColor = SottoTheme.secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissPanel)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // --- Transcript: a flipped document view holding the message stack ---
        transcript.orientation = .vertical
        transcript.alignment = .leading
        transcript.spacing = 10
        transcript.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(transcript)

        scrollView.documentView = doc
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(titleLabel)
        cv.addSubview(closeButton)
        cv.addSubview(separator)
        cv.addSubview(scrollView)

        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),

            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: clip.widthAnchor),

            transcript.topAnchor.constraint(equalTo: doc.topAnchor, constant: 14),
            transcript.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 16),
            transcript.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -16),
            transcript.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -14),
        ])
    }

    /// A full-width row hosting one bubble, pushed left (answer) or right
    /// (question); bubbles cap at ~78% of the transcript width.
    private func appendBubble(text: String, isUser: Bool) {
        let bubble = ChatBubble(text: text, isUser: isUser)
        let row = NSStackView(views: isUser ? [NSView(), bubble] : [bubble, NSView()])
        row.orientation = .horizontal
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        transcript.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalTo: transcript.widthAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.78),
        ])
    }

    private func scrollToBottom() {
        guard let doc = scrollView.documentView else { return }
        doc.layoutSubtreeIfNeeded()
        let y = max(0, doc.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Public

    /// Wipe the transcript — called when a new QA session starts after the
    /// panel was dismissed, alongside `LLMRefiner.resetQAConversation()`.
    func clearTranscript() {
        for view in transcript.arrangedSubviews {
            transcript.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    /// Append one Q&A exchange to the transcript and show the panel.
    func present(question: String, answer: String) {
        appendBubble(text: question, isUser: true)
        appendBubble(text: answer, isUser: false)

        if !isVisible, let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = frame.size
            // Upper-middle of the screen, out of the way of the bottom overlay.
            setFrameOrigin(NSPoint(
                x: area.midX - size.width / 2,
                y: area.minY + area.height * 0.62 - size.height / 2))
        }
        // Key (not just front): the panel must receive keyboard events for Esc
        // to dismiss it. Non-activating, so the user's app stays active and
        // regains key focus when the panel closes.
        let firstAppearance = !isVisible
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }

        // Materialize on first appearance: fade + a slight scale-up from the
        // center, so the surface reads as arriving, not a hard cut.
        if firstAppearance, let l = contentView?.layer {
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
            l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            l.position = CGPoint(x: l.bounds.midX, y: l.bounds.midY)
            let s = SottoTheme.spring(keyPath: "transform.scale", response: 0.32)
            s.fromValue = 0.965
            s.toValue = 1.0
            l.add(s, forKey: "materialize")
        }
    }

    // MARK: - Actions

    @objc private func dismissPanel() { orderOut(nil) }
}
