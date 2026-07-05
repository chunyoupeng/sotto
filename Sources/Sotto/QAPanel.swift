import AppKit

/// Floating panel that shows the answer to a spoken question (the QA hotkey).
/// Layout mirrors Typeless's fn+Space dialog — centered app title with a close
/// button, a question row (mic icon + copy), and an "answer" card with its own
/// header and copy button — rendered in Sotto's dark-glass theme.
/// Non-activating so the frontmost app keeps focus; Esc or ✕ dismisses.
final class QAPanel: NSPanel {
    private let questionLabel = NSTextField(wrappingLabelWithString: "")
    private let answerView = NSTextView()
    private let scrollView = NSScrollView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        SottoTheme.applyDarkGlass(to: self)
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 16
        contentView?.layer?.masksToBounds = true
        setupUI()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    // MARK: - UI

    private static func symbolButton(_ name: String, action: Selector, target: AnyObject) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.contentTintColor = SottoTheme.secondaryLabelColor
        b.target = target
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private static func symbolLabel(_ name: String) -> NSImageView {
        let v = NSImageView()
        v.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        v.contentTintColor = SottoTheme.secondaryLabelColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        // --- Header: centered app title, close button on the right ---
        let titleLabel = NSTextField(labelWithString: "Sotto")
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = SottoTheme.primaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = Self.symbolButton("xmark", action: #selector(dismissPanel), target: self)

        // --- Question row: mic + question + copy ---
        let micIcon = Self.symbolLabel("mic")
        questionLabel.font = .systemFont(ofSize: 13)
        questionLabel.textColor = SottoTheme.secondaryLabelColor
        questionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        let copyQuestionButton = Self.symbolButton(
            "doc.on.doc", action: #selector(copyQuestion), target: self)

        // --- Answer card ---
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        SottoTheme.styleAsCard(card)

        let sparkleIcon = Self.symbolLabel("sparkles")
        sparkleIcon.contentTintColor = SottoTheme.primaryLabelColor
        let answerTitle = NSTextField(labelWithString: "回答")
        answerTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        answerTitle.textColor = SottoTheme.primaryLabelColor
        answerTitle.translatesAutoresizingMaskIntoConstraints = false
        let copyAnswerButton = Self.symbolButton(
            "doc.on.doc", action: #selector(copyAnswer), target: self)

        let cardSeparator = NSBox()
        cardSeparator.boxType = .separator
        cardSeparator.translatesAutoresizingMaskIntoConstraints = false

        answerView.isEditable = false
        answerView.isSelectable = true
        answerView.drawsBackground = false
        answerView.font = .systemFont(ofSize: 14)
        answerView.textColor = SottoTheme.primaryLabelColor
        answerView.textContainerInset = NSSize(width: 12, height: 12)
        answerView.autoresizingMask = [.width]

        scrollView.documentView = answerView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(sparkleIcon)
        card.addSubview(answerTitle)
        card.addSubview(copyAnswerButton)
        card.addSubview(cardSeparator)
        card.addSubview(scrollView)

        cv.addSubview(titleLabel)
        cv.addSubview(closeButton)
        cv.addSubview(micIcon)
        cv.addSubview(questionLabel)
        cv.addSubview(copyQuestionButton)
        cv.addSubview(card)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),

            micIcon.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            micIcon.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            questionLabel.centerYAnchor.constraint(equalTo: micIcon.centerYAnchor),
            questionLabel.leadingAnchor.constraint(equalTo: micIcon.trailingAnchor, constant: 8),
            copyQuestionButton.centerYAnchor.constraint(equalTo: micIcon.centerYAnchor),
            copyQuestionButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: questionLabel.trailingAnchor, constant: 8),
            copyQuestionButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            card.topAnchor.constraint(equalTo: micIcon.bottomAnchor, constant: 14),
            card.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
            card.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),

            sparkleIcon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            sparkleIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            answerTitle.centerYAnchor.constraint(equalTo: sparkleIcon.centerYAnchor),
            answerTitle.leadingAnchor.constraint(equalTo: sparkleIcon.trailingAnchor, constant: 8),
            copyAnswerButton.centerYAnchor.constraint(equalTo: sparkleIcon.centerYAnchor),
            copyAnswerButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            cardSeparator.topAnchor.constraint(equalTo: sparkleIcon.bottomAnchor, constant: 12),
            cardSeparator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardSeparator.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: cardSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    // MARK: - Public

    func present(question: String, answer: String) {
        questionLabel.stringValue = question
        answerView.string = answer
        answerView.scrollToBeginningOfDocument(nil)

        if let screen = NSScreen.main {
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
        makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func dismissPanel() { orderOut(nil) }

    @objc private func copyQuestion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(questionLabel.stringValue, forType: .string)
    }

    @objc private func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answerView.string, forType: .string)
    }
}
