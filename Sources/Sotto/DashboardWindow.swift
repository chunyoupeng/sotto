import AppKit
import AVFoundation

/// Content of the menu-bar dashboard popover: today's stats, a 7-day bar chart,
/// lifetime totals, and a scrollable history of every dictation.
final class DashboardViewController: NSViewController {
    var onOpenSettings: (() -> Void)?

    private let todayLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let chart = BarChartView()
    private let table = NSTableView()
    private var rows: [DictationRecord] = []
    private var player: AVAudioPlayer?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 560))
        view = root
        preferredContentSize = root.frame.size

        // Dark glass background, shared with the overlay + settings.
        let bg = SottoTheme.makeVibrancyContainer(frame: root.bounds)
        root.addSubview(bg)

        let title = NSTextField(labelWithString: "Sotto 仪表盘")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = SottoTheme.primaryLabelColor

        todayLabel.font = .systemFont(ofSize: 13)
        todayLabel.textColor = SottoTheme.primaryLabelColor
        totalLabel.font = .systemFont(ofSize: 11)
        totalLabel.textColor = SottoTheme.secondaryLabelColor

        let chartCaption = NSTextField(labelWithString: "近 7 天（字数）")
        chartCaption.font = .systemFont(ofSize: 11)
        chartCaption.textColor = SottoTheme.secondaryLabelColor

        chart.translatesAutoresizingMaskIntoConstraints = false

        // History table
        table.headerView = nil
        table.rowHeight = 104
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(playSelected)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let historyCaption = NSTextField(labelWithString: "历史记录（点 ▶ 播放原音频）")
        historyCaption.font = .systemFont(ofSize: 11)
        historyCaption.textColor = SottoTheme.secondaryLabelColor

        let settingsBtn = NSButton(title: "设置…", target: self, action: #selector(openSettings))
        let exportBtn = NSButton(title: "导出 JSON", target: self, action: #selector(exportJSON))
        let clearBtn = NSButton(title: "清空", target: self, action: #selector(clearHistory))
        for b in [settingsBtn, exportBtn, clearBtn] { b.bezelStyle = .rounded }
        let buttonRow = NSStackView(views: [settingsBtn, exportBtn, NSView(), clearBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            title, todayLabel, totalLabel, chartCaption, chart,
            historyCaption, scroll, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        bg.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -16),
            chart.heightAnchor.constraint(equalToConstant: 90),
            chart.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func refresh() {
        let store = RecordStore.shared
        let today = store.todayStats()
        todayLabel.stringValue = String(
            format: "今日：%d 字 · %d 次 · 平均 %.0f 字/分",
            today.chars, today.count, today.charsPerMinute)
        totalLabel.stringValue = "累计：\(store.totalChars) 字 · \(store.totalCount) 次"
        chart.days = store.lastDays(7)
        rows = store.recent()
        table.reloadData()
    }

    // MARK: - Actions

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func playSelected() {
        let r = table.selectedRow
        guard r >= 0, r < rows.count, let url = RecordStore.shared.audioURL(for: rows[r]) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    @objc private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sotto-history.json"
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            let src = RecordStore.shared.baseDir.appendingPathComponent("history.json")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: src, to: dest)
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空所有历史记录？"
        alert.informativeText = "包括已保存的音频文件，此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            RecordStore.shared.clearAll()
            refresh()
        }
    }
}

extension DashboardViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = rows[row]
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? RecordCell) ?? RecordCell(identifier: id)
        let hasAudio = RecordStore.shared.audioURL(for: record) != nil
        cell.configure(with: record, hasAudio: hasAudio) { [weak self] in
            self?.play(record: record)
        }
        return cell
    }

    private func play(record: DictationRecord) {
        guard let url = RecordStore.shared.audioURL(for: record) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// A card history cell showing all three artifacts of one dictation:
/// the refined text (top, prominent), the raw ASR transcript (middle, dimmed),
/// and a play button for the original audio (when saved), plus a metadata line.
private final class RecordCell: NSView {
    private let card = NSView()
    private let refinedLabel = NSTextField(labelWithString: "")
    private let rawLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton()
    private var onPlay: (() -> Void)?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f
    }()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true

        SottoTheme.styleAsCard(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        // Refined text — the headline.
        refinedLabel.font = .systemFont(ofSize: 13, weight: .medium)
        refinedLabel.lineBreakMode = .byTruncatingTail
        refinedLabel.maximumNumberOfLines = 2
        refinedLabel.textColor = SottoTheme.primaryLabelColor
        refinedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Raw ASR transcript — secondary, so you can compare the model's output
        // against the refined result.
        rawLabel.font = .systemFont(ofSize: 11)
        rawLabel.lineBreakMode = .byTruncatingTail
        rawLabel.maximumNumberOfLines = 1
        rawLabel.textColor = SottoTheme.secondaryLabelColor
        rawLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = SottoTheme.secondaryLabelColor

        // Play button for the original audio.
        playButton.bezelStyle = .circular
        playButton.isBordered = false
        playButton.imagePosition = .imageOnly
        playButton.image = NSImage(systemSymbolName: "play.circle.fill",
                                    accessibilityDescription: "播放原音频")
        playButton.contentTintColor = NSColor(cgColor: SottoTheme.accent)
        playButton.target = self
        playButton.action = #selector(playTapped)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [refinedLabel, rawLabel, metaLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        card.addSubview(textStack)
        card.addSubview(playButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -10),

            playButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            playButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 26),
            playButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func playTapped() { onPlay?() }

    func configure(with r: DictationRecord, hasAudio: Bool, onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        refinedLabel.stringValue = r.refinedText.isEmpty ? "（空）" : "⚡ \(r.refinedText)"

        // Only show the raw line when it actually differs from the refined text.
        if !r.rawText.isEmpty && r.rawText != r.refinedText {
            rawLabel.stringValue = "识别原文：\(r.rawText)"
            rawLabel.isHidden = false
        } else {
            rawLabel.isHidden = true
        }

        metaLabel.stringValue = String(
            format: "%@ · %d 字 · %.1fs · %.0f 字/分",
            RecordCell.timeFmt.string(from: r.date),
            r.charCount, r.durationSeconds, r.charsPerMinute)

        playButton.isHidden = !hasAudio
    }
}

/// Minimal vertical bar chart for daily character counts.
private final class BarChartView: NSView {
    var days: [DayStats] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        let maxChars = max(days.map { $0.chars }.max() ?? 1, 1)
        let n = days.count
        let gap: CGFloat = 8
        let barW = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let labelH: CGFloat = 14
        let chartH = bounds.height - labelH

        let fmt = DateFormatter(); fmt.dateFormat = "d"

        // Cyan → indigo → violet, painted bottom-to-top on each bar.
        let colors = SottoTheme.palette.map { NSColor(cgColor: $0) ?? .white }
        guard let gradient = NSGradient(colors: colors) else { return }

        for (i, day) in days.enumerated() {
            let x = CGFloat(i) * (barW + gap)
            let frac = CGFloat(day.chars) / CGFloat(maxChars)
            let h = max(chartH * frac, day.chars > 0 ? 3 : 0)
            let rect = NSRect(x: x, y: labelH, width: barW, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            gradient.draw(in: path, angle: 90)

            let dayLabel = fmt.string(from: day.day) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: SottoTheme.secondaryLabelColor,
            ]
            let size = dayLabel.size(withAttributes: attrs)
            dayLabel.draw(at: NSPoint(x: x + (barW - size.width) / 2, y: 0), withAttributes: attrs)
        }
    }
}
