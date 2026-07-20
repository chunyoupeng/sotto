import AppKit

/// The main workspace window's content: an openless-style overview (engine
/// status, stat tiles, year heatmap, last-7-days + recent transcripts) and a
/// master–detail history browser whose edit path feeds local personalization.
final class DashboardViewController: NSViewController, NSSearchFieldDelegate {
    var onOpenSettings: (() -> Void)?

    private enum Page: Int, CaseIterable {
        case overview, history, dictionary, styles, tools

        var title: String {
            switch self {
            case .overview: return "概览"
            case .history: return "历史记录"
            case .dictionary: return "个人词典"
            case .styles: return "智能写作"
            case .tools: return "语音工具"
            }
        }

        var symbol: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .history: return "clock.arrow.circlepath"
            case .dictionary: return "character.book.closed"
            case .styles: return "wand.and.stars"
            case .tools: return "text.viewfinder"
            }
        }
    }

    // Overview widgets (long-lived; refresh() updates them in place).
    private let tileChars = StatTile(symbol: "number", caption: "今日字数")
    private let tileDuration = StatTile(symbol: "mic", caption: "今日时长")
    private let tileAvg = StatTile(symbol: "clock", caption: "平均每段")
    private let tileTotal = StatTile(symbol: "tray.full", caption: "总记录数", accented: true)
    private let chart = BarChartView()
    // The 近 7 天 card's bars show dictations or characters per day; the
    // 次数/字数 button rebuilds the page with this toggled.
    private var overviewChartShowsChars = false
    private let heatmap = HeatmapView()
    private let recentStack = NSStackView()

    // History master–detail state.
    private let table = NSTableView()
    private let historySearch = NSSearchField()
    private let historyCountLabel = NSTextField(labelWithString: "")
    private var filterChips: [ChipButton] = []
    private let historyDetailStack = NSStackView()
    private var historyAll: [DictationRecord] = []
    private var historyRows: [DictationRecord] = []
    private var historySelectedID: String?
    private enum HistoryFilter: Int, CaseIterable {
        case all = 0, corrected, uncorrected
        var title: String {
            switch self {
            case .all: return "全部"
            case .corrected: return "已修正"
            case .uncorrected: return "未修正"
            }
        }
    }
    private var historyFilter: HistoryFilter = .all
    // Usage-stats card under the history detail pane: range chips pick the
    // window, the trend chart re-buckets so long ranges stay readable.
    private var historyStatsRange = 7
    private var historyStatsShowsChars = false
    private var rangeChips: [ChipButton] = []
    private var metricChips: [ChipButton] = []
    private let historyStatsSummary = NSTextField(labelWithString: "")
    private let historyTrend = TrendChartView()

    private let contentHost = NSView()
    private var navButtons: [Page: SidebarButton] = [:]
    private var currentPage: Page = .overview
    private let dictionaryEditor = NSTextView()
    private let suggestionsStack = NSStackView()
    /// Sidebar badge showing which ASR backend is active; kept current by `refresh()`.
    private let asrBadgeLabel = NSTextField(labelWithString: "本地 ASR")

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f
    }()
    private static let groupFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 680))
        root.wantsLayer = true
        root.layer?.backgroundColor = SottoTheme.workspaceBackground.cgColor
        view = root

        // openless-style: sidebar and content share one surface — no divider
        // line, no separate sidebar color. The nav pills alone mark the zone.
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = SottoTheme.workspaceBackground.cgColor

        let mark = NSImageView(image: NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Sotto") ?? NSImage())
        mark.contentTintColor = SottoTheme.workspaceAccent
        mark.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        let brand = SottoTheme.displayLabel("Sotto", size: 18)
        let brandRow = NSStackView(views: [mark, brand])
        brandRow.orientation = .horizontal
        brandRow.alignment = .centerY
        brandRow.spacing = 9
        brandRow.translatesAutoresizingMaskIntoConstraints = false

        let section = SottoTheme.captionLabel("工作台")
        let nav = NSStackView()
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 4
        for page in Page.allCases {
            let button = SidebarButton(title: page.title, symbol: page.symbol, page: page.rawValue,
                                       target: self, action: #selector(navigate(_:)))
            nav.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
            navButtons[page] = button
        }

        let localBadge = makeSidebarStatus()
        let settings = SidebarButton(title: "设置", symbol: "gearshape", page: -1,
                                     target: self, action: #selector(openSettings))
        let sideStack = NSStackView(views: [brandRow, section, nav, NSView(), localBadge, settings])
        sideStack.orientation = .vertical
        sideStack.alignment = .leading
        sideStack.spacing = 12
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sideStack)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        root.addSubview(contentHost)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            // The reference uses a ~15% navigation rail (146 pt at 980 pt).
            sidebar.widthAnchor.constraint(equalToConstant: 146),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor),
            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            // The brand sits just below the traffic lights, like the reference.
            sideStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 25),
            sideStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sideStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            sideStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            nav.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
            settings.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
            localBadge.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
        ])

        // The window is intentionally NOT `.resizable`: under fullSizeContentView
        // the system edge hit-zone is swallowed by the content-filled surface,
        // and a `.resizable` mask also intercepts edge mouse-downs before this
        // view can see them. This transparent overlay owns all four edges itself.
        let resizeEdges = WindowResizeView()
        resizeEdges.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(resizeEdges, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            resizeEdges.topAnchor.constraint(equalTo: root.topAnchor),
            resizeEdges.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            resizeEdges.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            resizeEdges.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        configureTable()
        showPage(.overview, animated: false)
    }

    private func configureTable() {
        table.headerView = nil
        // Keep the master pane tall, but make each record compact so more
        // history remains visible at once.
        table.rowHeight = 74
        table.intercellSpacing = NSSize(width: 0, height: 5)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
    }

    private func makeSidebarStatus() -> NSView {
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 4
        let title = asrBadgeLabel
        title.font = .systemFont(ofSize: 11.5, weight: .medium)
        title.textColor = SottoTheme.workspaceSecondaryText
        let row = NSStackView(views: [dot, title])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let host = NSView()
        SottoTheme.styleAsCard(host)
        row.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(row)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -12),
        ])
        return host
    }

    @objc private func navigate(_ sender: SidebarButton) {
        guard let page = Page(rawValue: sender.page) else { return }
        showPage(page, animated: true)
    }

    private func showPage(_ page: Page, animated: Bool) {
        currentPage = page
        navButtons.forEach { $0.value.isSelected = $0.key == page }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let pageView: NSView
        switch page {
        case .overview: pageView = buildOverviewPage()
        case .history: pageView = buildHistoryPage()
        case .dictionary: pageView = buildDictionaryPage()
        case .styles: pageView = buildStylesPage()
        case .tools: pageView = buildToolsPage()
        }
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        if animated, let layer = pageView.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.16
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "page")
        }
        refresh()
    }

    private func pageHeader(_ title: String, subtitle: String = "",
                            eyebrow: String? = nil) -> NSStackView {
        let heading = SottoTheme.displayLabel(title, size: 24)
        var views: [NSView] = [heading]
        if let eyebrow {
            let label = SottoTheme.captionLabel(eyebrow.uppercased())
            views.insert(label, at: 0)
        }
        if !subtitle.isEmpty {
            let detail = NSTextField(wrappingLabelWithString: subtitle)
            detail.font = .systemFont(ofSize: 12.5)
            detail.textColor = SottoTheme.workspaceSecondaryText
            views.append(detail)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = eyebrow == nil ? 4 : 5
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }

    private func pageContainer(_ views: [NSView], spacing: CGFloat = 16) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.wantsLayer = true
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -24),
        ])
        return host
    }

    /// Wrap a vertical stack in a scroll view (flipped document so content
    /// hangs from the top). Used by the overview page and the history detail.
    private func scrollWrap(_ stack: NSStackView, topInset: CGFloat, sideInset: CGFloat,
                            bottomInset: CGFloat) -> NSScrollView {
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: topInset),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: sideInset),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -sideInset),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -bottomInset),
        ])
        return scroll
    }

    // MARK: - Overview page

    private func buildOverviewPage() -> NSView {
        let header = pageHeader("今日概览")

        let tiles = NSStackView(views: [tileChars, tileDuration, tileAvg, tileTotal])
        tiles.orientation = .horizontal
        tiles.distribution = .fillEqually
        tiles.spacing = 12

        // Year heatmap card.
        let heatCard = NSView()
        SottoTheme.styleAsCard(heatCard)
        let heatTitle = SottoTheme.captionLabel("年度活动")
        heatTitle.translatesAutoresizingMaskIntoConstraints = false
        heatmap.translatesAutoresizingMaskIntoConstraints = false
        heatCard.addSubview(heatTitle)
        heatCard.addSubview(heatmap)
        NSLayoutConstraint.activate([
            heatTitle.topAnchor.constraint(equalTo: heatCard.topAnchor, constant: 14),
            heatTitle.leadingAnchor.constraint(equalTo: heatCard.leadingAnchor, constant: 18),
            heatmap.topAnchor.constraint(equalTo: heatTitle.bottomAnchor, constant: 8),
            heatmap.leadingAnchor.constraint(equalTo: heatCard.leadingAnchor, constant: 18),
            heatmap.trailingAnchor.constraint(equalTo: heatCard.trailingAnchor, constant: -18),
            heatmap.bottomAnchor.constraint(equalTo: heatCard.bottomAnchor, constant: -12),
            heatmap.heightAnchor.constraint(equalToConstant: 110),
        ])

        // Last-7-days chart card. The 次数/字数 button flips the bars between
        // dictations per day and characters per day (page rebuilt in place).
        let chartCard = NSView()
        SottoTheme.styleAsCard(chartCard)
        let modeCaption = SottoTheme.captionLabel(overviewChartShowsChars ? "字 / 天" : "次 / 天")
        let modeToggle = CallbackButton(title: overviewChartShowsChars ? "次数" : "字数") { [weak self] in
            guard let self else { return }
            self.overviewChartShowsChars.toggle()
            self.showPage(.overview, animated: false)
        }
        let chartHeader = NSStackView(views: [
            SottoTheme.captionLabel("近 7 天"), NSView(), modeCaption, modeToggle])
        chartHeader.orientation = .horizontal
        chartHeader.alignment = .centerY
        chartHeader.spacing = 8
        chartHeader.translatesAutoresizingMaskIntoConstraints = false
        chart.translatesAutoresizingMaskIntoConstraints = false
        chartCard.addSubview(chartHeader)
        chartCard.addSubview(chart)
        NSLayoutConstraint.activate([
            chartHeader.topAnchor.constraint(equalTo: chartCard.topAnchor, constant: 16),
            chartHeader.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: 18),
            chartHeader.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -18),
            chart.topAnchor.constraint(equalTo: chartHeader.bottomAnchor, constant: 10),
            chart.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: 18),
            chart.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -18),
            chart.bottomAnchor.constraint(equalTo: chartCard.bottomAnchor, constant: -14),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 132),
        ])

        // Recent transcripts card.
        let recentCard = NSView()
        SottoTheme.styleAsCard(recentCard)
        let recentHeader = NSStackView(views: [
            SottoTheme.captionLabel("最近听写"), NSView(),
            CallbackButton(title: "查看全部", action: { [weak self] in
                self?.showPage(.history, animated: true)
            })])
        recentHeader.orientation = .horizontal
        recentHeader.alignment = .centerY
        recentHeader.translatesAutoresizingMaskIntoConstraints = false
        recentStack.orientation = .vertical
        recentStack.alignment = .leading
        recentStack.spacing = 6
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentCard.addSubview(recentHeader)
        recentCard.addSubview(recentStack)
        NSLayoutConstraint.activate([
            recentHeader.topAnchor.constraint(equalTo: recentCard.topAnchor, constant: 16),
            recentHeader.leadingAnchor.constraint(equalTo: recentCard.leadingAnchor, constant: 18),
            recentHeader.trailingAnchor.constraint(equalTo: recentCard.trailingAnchor, constant: -18),
            recentStack.topAnchor.constraint(equalTo: recentHeader.bottomAnchor, constant: 10),
            recentStack.leadingAnchor.constraint(equalTo: recentCard.leadingAnchor, constant: 12),
            recentStack.trailingAnchor.constraint(equalTo: recentCard.trailingAnchor, constant: -12),
            recentStack.bottomAnchor.constraint(lessThanOrEqualTo: recentCard.bottomAnchor, constant: -14),
        ])

        let bottomRow = NSStackView(views: [chartCard, recentCard])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .top
        bottomRow.spacing = 12

        let stack = NSStackView(views: [header, tiles, heatCard, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(9, after: header)
        for v in [tiles, heatCard, bottomRow] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        chartCard.widthAnchor.constraint(equalTo: bottomRow.widthAnchor, multiplier: 0.42).isActive = true
        chartCard.heightAnchor.constraint(equalTo: recentCard.heightAnchor).isActive = true

        return scrollWrap(stack, topInset: 18, sideInset: 22, bottomInset: 14)
    }

    private func recentRow(_ r: DictationRecord) -> NSView {
        let time = NSTextField(labelWithString: Self.timeFmt.string(from: r.date))
        time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        time.textColor = SottoTheme.workspaceSecondaryText
        time.setContentHuggingPriority(.required, for: .horizontal)
        let text = NSTextField(labelWithString: r.displayText.isEmpty ? "（空）" : r.displayText)
        text.font = .systemFont(ofSize: 12.5)
        text.textColor = SottoTheme.workspacePrimaryText
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let dur = NSTextField(labelWithString: String(format: "%.1fs", r.durationSeconds))
        dur.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dur.textColor = SottoTheme.workspaceSecondaryText
        dur.setContentHuggingPriority(.required, for: .horizontal)
        let copy = IconButton(symbol: "doc.on.doc", tooltip: "拷贝") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(r.displayText, forType: .string)
        }
        let edit = IconButton(symbol: "pencil", tooltip: "修正文本") { [weak self] in
            self?.editRecord(r)
        }
        let row = NSStackView(views: [time, text, NSView(), dur, copy, edit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        SottoTheme.styleAsWell(host, cornerRadius: 9)
        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: host.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
        ])
        return host
    }

    private func refreshOverview(_ store: RecordStore) {
        let today = store.todayStats()
        tileChars.value = Self.groupFmt.string(from: NSNumber(value: today.chars)) ?? "\(today.chars)"
        tileChars.sub = "\(today.count) 段"
        tileDuration.value = String(format: "%d:%02d", Int(today.seconds) / 60, Int(today.seconds) % 60)
        tileDuration.sub = "今日说话总时长"
        tileAvg.value = today.count > 0
            ? String(format: "%.1fs", today.seconds / Double(today.count)) : "—"
        tileAvg.sub = "今日平均每段"
        tileTotal.value = "\(store.totalCount)"
        let totalChars = Self.groupFmt.string(from: NSNumber(value: store.totalChars)) ?? ""
        tileTotal.sub = "本地存档 · 累计 \(totalChars) 字"

        chart.showsChars = overviewChartShowsChars
        chart.days = store.dailyStats(lastDays: 7)
        heatmap.days = store.dailyStats(lastDays: 365)

        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let recents = store.recent(limit: 4)
        if recents.isEmpty {
            let empty = NSTextField(labelWithString: "还没有听写记录。按住快捷键说话试试。")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = SottoTheme.workspaceSecondaryText
            recentStack.addArrangedSubview(empty)
        } else {
            for r in recents {
                let row = recentRow(r)
                recentStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true
            }
        }
    }

    // MARK: - History page (master–detail)

    private func buildHistoryPage() -> NSView {
        let host = NSView()
        host.wantsLayer = true

        let header = pageHeader(
            "历史记录",
            subtitle: "点击记录查看原文与润色对比；修正后的差异会成为个人词典候选",
            eyebrow: "History")
        header.translatesAutoresizingMaskIntoConstraints = false

        let export = CallbackButton(title: "导出 JSON") { [weak self] in self?.exportJSON() }
        let clear = CallbackButton(title: "清空历史", destructive: true) { [weak self] in
            self?.clearHistory()
        }
        let actions = NSStackView(views: [export, clear])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false

        // Master list card.
        let listCard = NSView()
        SottoTheme.styleAsCard(listCard)
        listCard.translatesAutoresizingMaskIntoConstraints = false

        historySearch.placeholderString = "搜索转写…"
        historySearch.font = .systemFont(ofSize: 12)
        historySearch.delegate = self
        historySearch.translatesAutoresizingMaskIntoConstraints = false

        historyCountLabel.font = .systemFont(ofSize: 11)
        historyCountLabel.textColor = SottoTheme.workspaceSecondaryText
        historyCountLabel.translatesAutoresizingMaskIntoConstraints = false

        filterChips = HistoryFilter.allCases.map { f in
            ChipButton(title: f.title, tag: f.rawValue,
                       target: self, action: #selector(chipClicked(_:)))
        }
        restyleChips()
        let chipRow = NSStackView(views: filterChips)
        chipRow.orientation = .horizontal
        chipRow.spacing = 6
        chipRow.translatesAutoresizingMaskIntoConstraints = false

        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.documentView = table
        listScroll.hasVerticalScroller = false
        listScroll.drawsBackground = false
        listScroll.borderType = .noBorder

        listCard.addSubview(historySearch)
        listCard.addSubview(historyCountLabel)
        listCard.addSubview(chipRow)
        listCard.addSubview(listScroll)

        // Detail pane (scrolls; long dictations wrap fully).
        historyDetailStack.orientation = .vertical
        historyDetailStack.alignment = .leading
        historyDetailStack.spacing = 12
        let detailScroll = scrollWrap(historyDetailStack, topInset: 2, sideInset: 2, bottomInset: 12)
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        // A bounded detail surface makes the unused lower area feel deliberate
        // (like the reference) instead of looking as though content is missing.
        let detailCard = NSView()
        SottoTheme.styleAsCard(detailCard)
        detailCard.translatesAutoresizingMaskIntoConstraints = false
        let detailFooter = SottoTheme.captionLabel("本地保存 · 可编辑 · 人工修正会生成个人词典候选")
        detailFooter.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(detailScroll)
        detailCard.addSubview(detailFooter)
        NSLayoutConstraint.activate([
            detailScroll.topAnchor.constraint(equalTo: detailCard.topAnchor, constant: 12),
            detailScroll.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 12),
            detailScroll.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -12),
            detailScroll.bottomAnchor.constraint(equalTo: detailFooter.topAnchor, constant: -8),
            detailFooter.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 16),
            detailFooter.trailingAnchor.constraint(lessThanOrEqualTo: detailCard.trailingAnchor, constant: -16),
            detailFooter.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: -12),
        ])

        // Usage-stats card (bottom-right): the overview's 7-day counter with a
        // time-range filter (7/30/90 天、一年) and a bucketed trend chart.
        let statsCard = NSView()
        SottoTheme.styleAsCard(statsCard)
        statsCard.translatesAutoresizingMaskIntoConstraints = false
        let ranges: [(days: Int, title: String)] = [
            (7, "7 天"), (30, "30 天"), (90, "90 天"), (365, "一年")]
        rangeChips = ranges.map {
            ChipButton(title: $0.title, tag: $0.days,
                       target: self, action: #selector(rangeChipClicked(_:)))
        }
        restyleRangeChips()
        let rangeRow = NSStackView(views: rangeChips)
        rangeRow.orientation = .horizontal
        rangeRow.spacing = 6
        // 次数/字数 picks the trend chart's metric, same as the overview card.
        metricChips = [(0, "次数"), (1, "字数")].map {
            ChipButton(title: $0.1, tag: $0.0,
                       target: self, action: #selector(metricChipClicked(_:)))
        }
        restyleMetricChips()
        let metricRow = NSStackView(views: metricChips)
        metricRow.orientation = .horizontal
        metricRow.spacing = 6
        let statsHeader = NSStackView(views: [
            SottoTheme.captionLabel("使用统计"), metricRow, NSView(), rangeRow])
        statsHeader.orientation = .horizontal
        statsHeader.alignment = .centerY
        statsHeader.spacing = 12
        statsHeader.translatesAutoresizingMaskIntoConstraints = false
        historyStatsSummary.font = .systemFont(ofSize: 11)
        historyStatsSummary.textColor = SottoTheme.workspaceSecondaryText
        historyStatsSummary.lineBreakMode = .byTruncatingTail
        historyStatsSummary.translatesAutoresizingMaskIntoConstraints = false
        historyTrend.translatesAutoresizingMaskIntoConstraints = false
        statsCard.addSubview(statsHeader)
        statsCard.addSubview(historyStatsSummary)
        statsCard.addSubview(historyTrend)
        NSLayoutConstraint.activate([
            statsHeader.topAnchor.constraint(equalTo: statsCard.topAnchor, constant: 12),
            statsHeader.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 16),
            statsHeader.trailingAnchor.constraint(equalTo: statsCard.trailingAnchor, constant: -16),
            historyStatsSummary.topAnchor.constraint(equalTo: statsHeader.bottomAnchor, constant: 8),
            historyStatsSummary.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 16),
            historyStatsSummary.trailingAnchor.constraint(lessThanOrEqualTo: statsCard.trailingAnchor, constant: -16),
            historyTrend.topAnchor.constraint(equalTo: historyStatsSummary.bottomAnchor, constant: 8),
            historyTrend.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 16),
            historyTrend.trailingAnchor.constraint(equalTo: statsCard.trailingAnchor, constant: -16),
            historyTrend.bottomAnchor.constraint(equalTo: statsCard.bottomAnchor, constant: -10),
        ])

        host.addSubview(header)
        host.addSubview(actions)
        host.addSubview(listCard)
        host.addSubview(detailCard)
        host.addSubview(statsCard)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: host.topAnchor, constant: 17),
            header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 22),
            actions.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -22),
            actions.topAnchor.constraint(equalTo: host.topAnchor, constant: 17),
            header.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),

            listCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 13),
            listCard.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 22),
            // Give transcript previews enough line width to be useful without
            // stealing space from the now vertically stacked detail cards.
            listCard.widthAnchor.constraint(equalToConstant: 340),
            listCard.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14),

            detailCard.topAnchor.constraint(equalTo: listCard.topAnchor),
            detailCard.leadingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: 12),
            detailCard.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -22),
            detailCard.bottomAnchor.constraint(equalTo: statsCard.topAnchor, constant: -12),

            statsCard.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            statsCard.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            statsCard.bottomAnchor.constraint(equalTo: listCard.bottomAnchor),
            statsCard.heightAnchor.constraint(equalToConstant: 208),

            historySearch.topAnchor.constraint(equalTo: listCard.topAnchor, constant: 12),
            historySearch.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 12),
            historySearch.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -12),
            historyCountLabel.topAnchor.constraint(equalTo: historySearch.bottomAnchor, constant: 10),
            historyCountLabel.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 14),
            chipRow.topAnchor.constraint(equalTo: historyCountLabel.bottomAnchor, constant: 8),
            chipRow.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 12),
            chipRow.trailingAnchor.constraint(lessThanOrEqualTo: listCard.trailingAnchor, constant: -12),
            listScroll.topAnchor.constraint(equalTo: chipRow.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 6),
            listScroll.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -6),
            listScroll.bottomAnchor.constraint(equalTo: listCard.bottomAnchor, constant: -6),
        ])
        return host
    }

    @objc private func chipClicked(_ sender: ChipButton) {
        historyFilter = HistoryFilter(rawValue: sender.tag) ?? .all
        restyleChips()
        applyHistoryFilter()
    }

    private func restyleChips() {
        for chip in filterChips { chip.isOn = chip.tag == historyFilter.rawValue }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === historySearch else { return }
        applyHistoryFilter()
    }

    private func applyHistoryFilter() {
        let query = historySearch.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        historyRows = historyAll.filter { r in
            switch historyFilter {
            case .all: break
            case .corrected: if !r.isCorrected { return false }
            case .uncorrected: if r.isCorrected { return false }
            }
            guard !query.isEmpty else { return true }
            return r.displayText.lowercased().contains(query)
                || r.rawText.lowercased().contains(query)
        }
        historyCountLabel.stringValue = "共 \(historyAll.count) 条 · 显示 \(historyRows.count) 条"
        table.reloadData()
        if let id = historySelectedID,
           let idx = historyRows.firstIndex(where: { $0.id == id }) {
            table.selectRowIndexes([idx], byExtendingSelection: false)
            // Reselecting the same row does not always emit a selection-change
            // notification. Refresh explicitly so an editor save immediately
            // turns this pane into the new before/after diff.
            updateHistoryDetail()
        } else if !historyRows.isEmpty {
            historySelectedID = historyRows[0].id
            table.selectRowIndexes([0], byExtendingSelection: false)
            updateHistoryDetail()
        } else {
            historySelectedID = nil
            updateHistoryDetail()
        }
    }

    private func refreshHistory(_ store: RecordStore) {
        historyAll = store.recent(limit: 500)
        applyHistoryFilter()
        updateHistoryStats()
    }

    @objc private func rangeChipClicked(_ sender: ChipButton) {
        historyStatsRange = sender.tag
        restyleRangeChips()
        updateHistoryStats()
    }

    private func restyleRangeChips() {
        for chip in rangeChips { chip.isOn = chip.tag == historyStatsRange }
    }

    @objc private func metricChipClicked(_ sender: ChipButton) {
        historyStatsShowsChars = sender.tag == 1
        restyleMetricChips()
        updateHistoryStats()
    }

    private func restyleMetricChips() {
        for chip in metricChips { chip.isOn = (chip.tag == 1) == historyStatsShowsChars }
    }

    private func updateHistoryStats() {
        let days = RecordStore.shared.dailyStats(lastDays: historyStatsRange)
        let count = days.reduce(0) { $0 + $1.count }
        let chars = days.reduce(0) { $0 + $1.chars }
        let secs = days.reduce(0.0) { $0 + $1.seconds }
        let charsText = Self.groupFmt.string(from: NSNumber(value: chars)) ?? "\(chars)"
        historyStatsSummary.stringValue = String(
            format: "共 %d 次 · %@ 字 · %d 分钟 · 平均每天 %.1f 次",
            count, charsText, Int(secs / 60),
            Double(count) / Double(max(historyStatsRange, 1)))
        historyTrend.buckets = Self.trendBuckets(
            days, rangeDays: historyStatsRange,
            value: historyStatsShowsChars ? { $0.chars } : { $0.count })
    }

    /// Daily buckets for short ranges, weekly around 90 days, monthly for a
    /// year — keeps the trend chart readable at every zoom level. `value`
    /// picks the plotted metric (dictation count or characters).
    private static func trendBuckets(_ days: [DayStats], rangeDays: Int,
                                     value: (DayStats) -> Int) -> [TrendChartView.Bucket] {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "M/d"
        if rangeDays <= 30 {
            return days.map { .init(label: dayFmt.string(from: $0.day), value: value($0)) }
        }
        if rangeDays <= 120 {
            return stride(from: 0, to: days.count, by: 7).map { i in
                let slice = days[i..<min(i + 7, days.count)]
                return .init(label: dayFmt.string(from: slice.first!.day),
                             value: slice.reduce(0) { $0 + value($1) })
            }
        }
        let cal = Calendar.current
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "M月"
        var out: [TrendChartView.Bucket] = []
        var lastMonth: DateComponents?
        for d in days {
            let key = cal.dateComponents([.year, .month], from: d.day)
            if key == lastMonth, let prev = out.last {
                out[out.count - 1] = .init(label: prev.label, value: prev.value + value(d))
            } else {
                lastMonth = key
                out.append(.init(label: monthFmt.string(from: d.day), value: value(d)))
            }
        }
        return out
    }

    private static func tagInfo(_ r: DictationRecord) -> (text: String, color: NSColor) {
        if r.isCorrected {
            return ("已修正", NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.55, alpha: 1))
        }
        if r.refinedText != r.rawText { return ("已润色", SottoTheme.workspaceAccent) }
        return ("原文", NSColor(calibratedWhite: 0.62, alpha: 1))
    }

    private func updateHistoryDetail() {
        historyDetailStack.arrangedSubviews.forEach {
            historyDetailStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let record = historyRows.first(where: { $0.id == historySelectedID }) else {
            let empty = NSTextField(labelWithString:
                historyRows.isEmpty ? "没有匹配的记录。" : "在左侧选择一条记录。")
            empty.font = .systemFont(ofSize: 12.5)
            empty.textColor = SottoTheme.workspaceSecondaryText
            historyDetailStack.addArrangedSubview(empty)
            return
        }

        let time = NSTextField(labelWithString: Self.dateTimeFmt.string(from: record.date))
        time.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        time.textColor = SottoTheme.workspacePrimaryText
        let tag = Self.tagInfo(record)
        let dur = NSTextField(labelWithString: String(format: "%.1fs", record.durationSeconds))
        dur.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dur.textColor = SottoTheme.workspaceSecondaryText

        let edit = CallbackButton(title: "编辑", primary: true) { [weak self] in
            self?.editRecord(record)
        }
        let copy = CallbackButton(title: "拷贝") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.displayText, forType: .string)
        }
        let delete = CallbackButton(title: "删除", destructive: true) { [weak self] in
            self?.deleteRecord(record)
        }
        let headerRow = NSStackView(views: [
            time, PillTag(text: tag.text, color: tag.color), dur, NSView(), copy, delete, edit])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        // Before correction this mirrors OpenLess' Raw / polish comparison.
        // After an edit it becomes a true before / after diff immediately.
        let beforeCaption = record.isCorrected ? "修改前（润色结果）" : "识别原文（ASR）"
        let beforeText = record.isCorrected ? record.refinedText : record.rawText
        let afterCaption = record.isCorrected ? "人工修正后" : "润色结果"
        let beforeCard = detailTextCard(caption: beforeCaption, text: beforeText,
                                        accented: false)
        let afterCard = detailTextCard(caption: afterCaption, text: record.displayText,
                                       accented: true)
        let comparisonRow = NSStackView(views: [beforeCard, afterCard])
        comparisonRow.orientation = .vertical
        comparisonRow.alignment = .leading
        comparisonRow.distribution = .fill
        comparisonRow.spacing = 10
        beforeCard.widthAnchor.constraint(equalTo: comparisonRow.widthAnchor).isActive = true
        afterCard.widthAnchor.constraint(equalTo: comparisonRow.widthAnchor).isActive = true

        let candidate = record.correctedText.flatMap {
            PersonalizationStore.correctionCandidate(before: record.refinedText, after: $0)
        }
        var metaText = String(
            format: "%d 字 · %.1f 秒 · %.0f 字/分",
            record.charCount, record.durationSeconds, record.charsPerMinute)
        if let candidate, AppSettings.autoLearnDictionary {
            metaText += " · 词典候选：\(candidate.source) → \(candidate.replacement)"
        } else if record.isCorrected {
            metaText += " · 修正已保存；本次差异不适合作为词典词条"
        }
        let meta = NSTextField(wrappingLabelWithString: metaText)
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = SottoTheme.workspaceSecondaryText

        for v in [headerRow, comparisonRow, meta] {
            historyDetailStack.addArrangedSubview(v)
        }
        headerRow.widthAnchor.constraint(equalTo: historyDetailStack.widthAnchor).isActive = true
        comparisonRow.widthAnchor.constraint(equalTo: historyDetailStack.widthAnchor).isActive = true
    }

    private func detailTextCard(caption: String, text: String, accented: Bool) -> NSView {
        let card = NSView()
        if accented {
            card.wantsLayer = true
            card.layer?.cornerRadius = SottoTheme.cardCornerRadius
            card.layer?.backgroundColor = SottoTheme.workspaceAccent.withAlphaComponent(0.07).cgColor
            card.layer?.borderWidth = 1
            card.layer?.borderColor = SottoTheme.workspaceAccent.withAlphaComponent(0.45).cgColor
        } else {
            SottoTheme.styleAsWell(card, cornerRadius: SottoTheme.cardCornerRadius)
        }
        let cap = SottoTheme.captionLabel(caption)
        let body = NSTextField(wrappingLabelWithString: text.isEmpty ? "（空）" : text)
        body.font = .systemFont(ofSize: 12)
        body.textColor = accented ? SottoTheme.workspacePrimaryText : SottoTheme.workspaceSecondaryText
        body.isSelectable = true
        let stack = NSStackView(views: [cap, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return card
    }

    private func deleteRecord(_ record: DictationRecord) {
        let alert = NSAlert()
        alert.messageText = "删除这条记录？"
        alert.informativeText = "此操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        RecordStore.shared.remove(id: record.id)
        if historySelectedID == record.id { historySelectedID = nil }
        refresh()
    }

    // MARK: - Other pages (unchanged layouts)

    private func buildDictionaryPage() -> NSView {
        let header = pageHeader("个人词典", subtitle: "热词同时进入本地 ASR 和润色层；人工修正只生成候选，由你确认后生效")
        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = false
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        SottoTheme.styleAsWell(editorScroll, cornerRadius: 10)
        dictionaryEditor.isRichText = false
        dictionaryEditor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        dictionaryEditor.textColor = SottoTheme.workspacePrimaryText
        dictionaryEditor.insertionPointColor = SottoTheme.workspacePrimaryText
        dictionaryEditor.drawsBackground = false
        dictionaryEditor.string = SottoConfig.readHotwordsRaw()
        dictionaryEditor.autoresizingMask = [.width]
        dictionaryEditor.isVerticallyResizable = true
        dictionaryEditor.isHorizontallyResizable = false
        dictionaryEditor.textContainer?.widthTracksTextView = true
        dictionaryEditor.frame = NSRect(x: 0, y: 0, width: 600, height: 210)
        editorScroll.documentView = dictionaryEditor
        editorScroll.heightAnchor.constraint(equalToConstant: 210).isActive = true

        let save = CallbackButton(title: "保存词典", primary: true) { [weak self] in
            guard let self else { return }
            SottoConfig.writeHotwords(self.dictionaryEditor.string)
            self.showPage(.dictionary, animated: false)
        }
        let open = CallbackButton(title: "打开 hotwords.txt") {
            NSWorkspace.shared.activateFileViewerSelecting([SottoConfig.hotwordsURL])
        }
        let actionRow = NSStackView(views: [save, open, NSView()])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        suggestionsStack.orientation = .vertical
        suggestionsStack.alignment = .leading
        suggestionsStack.spacing = 8
        suggestionsStack.arrangedSubviews.forEach {
            suggestionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let pendingSuggestions = PersonalizationStore.suggestions
        for suggestion in pendingSuggestions.prefix(3) {
            let text = NSTextField(labelWithString:
                "\(suggestion.source)  →  \(suggestion.replacement)" +
                (suggestion.occurrences > 1 ? "  ×\(suggestion.occurrences)" : ""))
            text.font = .systemFont(ofSize: 12, weight: .medium)
            text.textColor = SottoTheme.workspacePrimaryText
            let accept = CallbackButton(title: "加入词典", primary: true) { [weak self] in
                PersonalizationStore.acceptSuggestion(id: suggestion.id)
                self?.showPage(.dictionary, animated: false)
            }
            let dismiss = CallbackButton(title: "忽略") { [weak self] in
                PersonalizationStore.dismissSuggestion(id: suggestion.id)
                self?.showPage(.dictionary, animated: false)
            }
            let row = NSStackView(views: [text, NSView(), dismiss, accept])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            let card = NSView()
            SottoTheme.styleAsCard(card)
            row.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            ])
            suggestionsStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: suggestionsStack.widthAnchor).isActive = true
        }
        if PersonalizationStore.suggestions.isEmpty {
            let empty = NSTextField(labelWithString: "还没有待确认的纠错词。你在历史里修正文字后，候选会出现在这里。")
            empty.textColor = SottoTheme.workspaceSecondaryText
            empty.font = .systemFont(ofSize: 12)
            suggestionsStack.addArrangedSubview(empty)
        } else if pendingSuggestions.count > 3 {
            let more = NSTextField(labelWithString: "另有 \(pendingSuggestions.count - 3) 条候选；处理上面的候选后会继续显示。")
            more.textColor = SottoTheme.workspaceSecondaryText
            more.font = .systemFont(ofSize: 11)
            suggestionsStack.addArrangedSubview(more)
        }
        let host = pageContainer([
            header, SottoTheme.captionLabel("热词文件"), editorScroll, actionRow,
            SottoTheme.captionLabel("从修正中学习"), suggestionsStack,
        ])
        for v in [editorScroll, actionRow, suggestionsStack] {
            v.widthAnchor.constraint(equalTo: host.subviews.first!.widthAnchor).isActive = true
        }
        return host
    }

    private func buildStylesPage() -> NSView {
        let header = pageHeader("智能写作", subtitle: "把 Typeless 式自然听写拆成可控、可关闭的本地策略")
        let learned = PersonalizationStore.profile.correctionCount
        let profile = (PersonalizationStore.promptSummary
            ?? "完成第一次人工修正后，Sotto 会在本地生成简短写作偏好。")
            + "\n已从 \(learned) 次明确修正中学习。"
        let profileCard = featureCard(
            symbol: "person.text.rectangle", title: "你的写作档案", detail: profile,
            enabled: AppSettings.personalizationEnabled, tag: 1)
        let appCard = featureCard(
            symbol: "app.badge", title: "按应用调整语气",
            detail: "邮件完整专业；聊天简洁自然；IDE 保留代码、路径和 Markdown。",
            enabled: AppSettings.appAwareToneEnabled, tag: 2)
        let selectionCard = featureCard(
            symbol: "text.viewfinder", title: "选中文本助手",
            detail: "选中文字后按问答快捷键，说“缩短一点”“解释一下”或“翻译成英文”。",
            enabled: AppSettings.selectionAssistantEnabled, tag: 3)
        let whisperCard = featureCard(
            symbol: "waveform.badge.mic", title: "轻声模式",
            detail: "录音阶段使用软限幅增益，提高低音量、近距离耳语的可识别度。",
            enabled: AppSettings.whisperModeEnabled, tag: 4)
        let dictionaryCard = featureCard(
            symbol: "character.book.closed", title: "纠错学习",
            detail: "人工修正会生成待确认词典候选，不会静默污染热词。",
            enabled: AppSettings.autoLearnDictionary, tag: 5)
        let muteCard = featureCard(
            symbol: "speaker.slash", title: "录音时静音系统声音",
            detail: "按下说话时自动静音扬声器输出，结束后恢复原状态，避免背景音乐混入听写。",
            enabled: AppSettings.muteWhileRecording, tag: 6)
        let cards = [profileCard, appCard, selectionCard, whisperCard, dictionaryCard, muteCard]
        let host = pageContainer([header] + cards, spacing: 12)
        for card in cards {
            card.widthAnchor.constraint(equalTo: host.subviews.first!.widthAnchor).isActive = true
        }
        return host
    }

    private func featureCard(symbol: String, title: String, detail: String,
                             enabled: Bool, tag: Int, showsToggle: Bool = true) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
        icon.contentTintColor = SottoTheme.workspaceAccent
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = SottoTheme.workspacePrimaryText
        let body = NSTextField(wrappingLabelWithString: detail)
        body.font = .systemFont(ofSize: 12)
        body.textColor = SottoTheme.workspaceSecondaryText
        let copy = NSStackView(views: [heading, body])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        let toggle = NSButton(checkboxWithTitle: "启用", target: self, action: #selector(featureChanged(_:)))
        toggle.tag = tag
        toggle.state = enabled ? .on : .off
        toggle.isHidden = !showsToggle
        let row = NSStackView(views: [icon, copy, NSView(), toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        let card = NSView()
        SottoTheme.styleAsCard(card)
        card.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    @objc private func featureChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender.tag {
        case 1: AppSettings.personalizationEnabled = on
        case 2: AppSettings.appAwareToneEnabled = on
        case 3: AppSettings.selectionAssistantEnabled = on
        case 4: AppSettings.whisperModeEnabled = on
        case 5: AppSettings.autoLearnDictionary = on
        case 6: AppSettings.muteWhileRecording = on
        default: break
        }
        showPage(.styles, animated: false)
    }

    private func buildToolsPage() -> NSView {
        let header = pageHeader("语音工具", subtitle: "在任何应用中听写、翻译、提问或直接处理选中文字")
        let dictate = shortcutCard("听写", shortcut: AppSettings.holdHotkey.displayString,
                                   detail: "自然说话，自动去口癖、重复和改口，再写入光标位置。")
        let translate = shortcutCard("翻译", shortcut: AppSettings.translateHotkey.displayString,
                                     detail: "把口述内容翻译成 \(LLMRefiner.shared.translateTargetLanguage) 后写入。")
        let ask = shortcutCard("Ask Anything", shortcut: AppSettings.qaHotkey.displayString,
                               detail: "无选区时语音问答；有选区时改写、总结、解释或翻译。")
        let host = pageContainer([header, dictate, translate, ask])
        for card in [dictate, translate, ask] {
            card.widthAnchor.constraint(equalTo: host.subviews.first!.widthAnchor).isActive = true
        }
        return host
    }

    private func shortcutCard(_ title: String, shortcut: String, detail: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = SottoTheme.workspacePrimaryText
        let body = NSTextField(wrappingLabelWithString: detail)
        body.font = .systemFont(ofSize: 12)
        body.textColor = SottoTheme.workspaceSecondaryText
        let copy = NSStackView(views: [heading, body])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4
        let key = NSTextField(labelWithString: shortcut)
        key.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        key.textColor = SottoTheme.workspaceAccent
        let row = NSStackView(views: [copy, NSView(), key])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        let card = NSView()
        SottoTheme.styleAsCard(card)
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    func refresh() {
        asrBadgeLabel.stringValue = AppSettings.asrBackend == .openAI ? "在线 ASR" : "本地 ASR"
        let store = RecordStore.shared
        switch currentPage {
        case .overview: refreshOverview(store)
        case .history: refreshHistory(store)
        default: break
        }
    }

    // MARK: - Actions

    @objc private func openSettings() { onOpenSettings?() }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sotto-history.json"
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            let src = RecordStore.shared.baseDir.appendingPathComponent("history.json")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: src, to: dest)
        }
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空所有历史记录？"
        alert.informativeText = "此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            RecordStore.shared.clearAll()
            historySelectedID = nil
            refresh()
        }
    }

    private func editRecord(_ record: DictationRecord) {
        RecordEditorWindowController.present(for: record) { [weak self] corrected in
            RecordStore.shared.setCorrection(id: record.id, correctedText: corrected)
            self?.refresh()
        }
    }
}

extension DashboardViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { historyRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = historyRows[row]
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryListCell)
            ?? HistoryListCell(identifier: id)
        cell.configure(with: record, selected: row == tableView.selectedRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let sel = table.selectedRow
        historySelectedID = (sel >= 0 && sel < historyRows.count) ? historyRows[sel].id : nil
        table.enumerateAvailableRowViews { rowView, row in
            (rowView.view(atColumn: 0) as? HistoryListCell)?.setSelected(row == sel)
        }
        updateHistoryDetail()
    }
}

/// AppKit's default view coordinates grow upward; scroll documents want
/// top-down flow.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Flat sidebar item used by the desktop workspace.
private final class SidebarButton: NSButton {
    let page: Int
    var isSelected: Bool = false { didSet { restyle() } }

    init(title: String, symbol: String, page: Int, target: AnyObject?, action: Selector?) {
        self.page = page
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageHugsTitle = true
        alignment = .left
        wantsLayer = true
        layer?.cornerRadius = 7
        toolTip = title
        setAccessibilityLabel(title)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: max(base.width + 20, 120), height: 34)
    }

    private func restyle() {
        // openless-style selection: a quiet neutral pill with white text, not
        // an accent-tinted one — the accent stays reserved for content.
        let foreground = isSelected ? SottoTheme.workspacePrimaryText : SottoTheme.workspaceSecondaryText
        contentTintColor = foreground
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .medium),
            .foregroundColor: foreground,
        ])
        layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.09).cgColor
            : NSColor.clear.cgColor
    }
}

/// Small workspace action with a closure-based API.
private final class CallbackButton: NSButton {
    private let callback: () -> Void

    init(title: String, primary: Bool = false, destructive: Bool = false,
         action: @escaping () -> Void) {
        callback = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(fire)
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = primary ? 0 : 1
        layer?.borderColor = SottoTheme.workspaceLine.cgColor
        layer?.backgroundColor = primary
            ? SottoTheme.workspaceAccent.cgColor
            : SottoTheme.workspaceSurface.cgColor
        let foreground: NSColor = destructive ? .systemRed : (primary ? .black : SottoTheme.workspacePrimaryText)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: foreground,
        ])
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 22, height: 30)
    }

    @objc private func fire() { callback() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        alphaValue = 0.76
        super.mouseDown(with: event)
        alphaValue = 1
    }
}

/// Icon-only action (copy / edit) used inside list rows.
private final class IconButton: NSButton {
    private let callback: () -> Void

    init(symbol: String, tooltip: String, action: @escaping () -> Void) {
        callback = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(fire)
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        contentTintColor = SottoTheme.workspaceSecondaryText
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    @objc private func fire() { callback() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        alphaValue = 0.6
        super.mouseDown(with: event)
        alphaValue = 1
    }
}

/// openless-style filter chip: accent capsule when on, quiet outline when off.
private final class ChipButton: NSButton {
    var isOn: Bool = false { didSet { restyle() } }

    init(title: String, tag: Int, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.tag = tag
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 11
        setAccessibilityLabel(title)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 18, height: 22)
    }

    private func restyle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isOn ? NSColor.black : SottoTheme.workspaceSecondaryText,
        ])
        layer?.backgroundColor = isOn
            ? SottoTheme.workspaceAccent.cgColor
            : SottoTheme.workspaceSurface.cgColor
        layer?.borderWidth = isOn ? 0 : 1
        layer?.borderColor = SottoTheme.workspaceLine.cgColor
    }
}

/// A tiny rounded tag ("已修正" / "已润色" / "原文").
private final class PillTag: NSView {
    private let label: NSTextField

    init(text: String, color: NSColor) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 8
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2.5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2.5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
        ])
    }

    override var intrinsicContentSize: NSSize {
        let size = label.intrinsicContentSize
        return NSSize(width: size.width + 14, height: size.height + 5)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// One glanceable metric on a card, openless-style: an icon+caption row, a big
/// monospaced-digit value, and a muted sub-caption.
private final class StatTile: NSView {
    private let valueLabel = NSTextField(labelWithString: "0")
    private let subLabel = NSTextField(labelWithString: "")

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    var sub: String {
        get { subLabel.stringValue }
        set { subLabel.stringValue = newValue }
    }

    init(symbol: String, caption: String, accented: Bool = false) {
        super.init(frame: .zero)
        SottoTheme.styleAsCard(self)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol,
                                              accessibilityDescription: caption) ?? NSImage())
        icon.contentTintColor = SottoTheme.workspaceSecondaryText
        icon.symbolConfiguration = .init(pointSize: 10.5, weight: .medium)
        let cap = NSTextField(labelWithString: "")
        cap.attributedStringValue = NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: SottoTheme.workspaceSecondaryText,
            .kern: 0.3,
        ])
        let capRow = NSStackView(views: [icon, cap])
        capRow.orientation = .horizontal
        capRow.alignment = .centerY
        capRow.spacing = 5

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .semibold)
        valueLabel.textColor = accented ? SottoTheme.workspaceAccent : SottoTheme.workspacePrimaryText
        valueLabel.lineBreakMode = .byTruncatingTail

        subLabel.font = .systemFont(ofSize: 10.5)
        subLabel.textColor = SottoTheme.workspaceSecondaryText
        subLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [capRow, valueLabel, subLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// History master-list cell: time + duration line, compact text, a state tag.
/// Selection is an accent-tinted card, restyled in place (no reload needed).
private final class HistoryListCell: NSView {
    private let card = NSView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let durLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private var tagHost = NSView()
    private var selected = false

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

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = SottoTheme.workspaceSecondaryText
        durLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durLabel.textColor = SottoTheme.workspaceSecondaryText

        textLabel.font = .systemFont(ofSize: 12.5)
        textLabel.textColor = SottoTheme.workspacePrimaryText
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 2
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [timeLabel, NSView(), durLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        tagHost.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(topRow)
        card.addSubview(textLabel)
        card.addSubview(tagHost)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            textLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 2),
            textLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            tagHost.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 3),
            tagHost.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            tagHost.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with r: DictationRecord, selected: Bool) {
        timeLabel.stringValue = Self.timeFmt.string(from: r.date)
        durLabel.stringValue = String(format: "%.1fs", r.durationSeconds)
        textLabel.stringValue = r.displayText.isEmpty ? "（空）" : r.displayText

        tagHost.subviews.forEach { $0.removeFromSuperview() }
        let tag: (text: String, color: NSColor)
        if r.isCorrected {
            tag = ("已修正", NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.55, alpha: 1))
        } else if r.refinedText != r.rawText {
            tag = ("已润色", SottoTheme.workspaceAccent)
        } else {
            tag = ("原文", NSColor(calibratedWhite: 0.62, alpha: 1))
        }
        let pill = PillTag(text: tag.text, color: tag.color)
        pill.translatesAutoresizingMaskIntoConstraints = false
        tagHost.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: tagHost.topAnchor),
            pill.bottomAnchor.constraint(equalTo: tagHost.bottomAnchor),
            pill.leadingAnchor.constraint(equalTo: tagHost.leadingAnchor),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: tagHost.trailingAnchor),
        ])

        setSelected(selected)
    }

    func setSelected(_ on: Bool) {
        selected = on
        guard let l = card.layer else { return }
        l.backgroundColor = on
            ? SottoTheme.workspaceAccent.withAlphaComponent(0.10).cgColor
            : SottoTheme.workspaceSurface.cgColor
        l.borderColor = on
            ? SottoTheme.workspaceAccent.withAlphaComponent(0.40).cgColor
            : SottoTheme.workspaceLine.cgColor
    }
}

/// Minimal vertical bar chart of dictations per day, openless-style: the count
/// above every bar, the weekday under it.
private final class BarChartView: NSView {
    var days: [DayStats] = [] { didSet { needsDisplay = true } }
    /// False: dictations per day; true: characters per day.
    var showsChars = false { didSet { needsDisplay = true } }

    private let gap: CGFloat = 8
    private let labelH: CGFloat = 14
    private let valueH: CGFloat = 14

    private func value(_ d: DayStats) -> Int { showsChars ? d.chars : d.count }

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        let maxCount = max(days.map { value($0) }.max() ?? 1, 1)
        let chartH = bounds.height - labelH - valueH

        // Hairline baseline anchors the bars to a common ground plane.
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: labelH - 1, width: bounds.width, height: 1).fill()

        let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
        let cal = Calendar.current

        // The workspace uses one calm blue accent; richer state gradients stay
        // reserved for the floating recording overlay.
        guard let gradient = NSGradient(
            starting: SottoTheme.workspaceAccent.withAlphaComponent(0.58),
            ending: SottoTheme.workspaceAccent
        ) else { return }

        let n = max(days.count, 1)
        let barW = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        for (i, day) in days.enumerated() {
            let x = CGFloat(i) * (barW + gap)
            let v = value(day)
            let frac = CGFloat(v) / CGFloat(maxCount)
            let h = max(chartH * frac, v > 0 ? 3 : 0)
            if v > 0 {
                let rect = NSRect(x: x, y: labelH, width: barW, height: h)
                gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4), angle: 90)
            }

            let isToday = i == days.count - 1
            let value = "\(v)" as NSString
            let vAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: isToday ? .semibold : .regular),
                .foregroundColor: isToday ? SottoTheme.workspaceAccent : SottoTheme.secondaryLabelColor,
            ]
            let vSize = value.size(withAttributes: vAttrs)
            let vy = min(labelH + h + 3, bounds.height - vSize.height)
            value.draw(at: NSPoint(x: x + (barW - vSize.width) / 2, y: vy), withAttributes: vAttrs)

            let weekday = weekdayNames[cal.component(.weekday, from: day.day) - 1] as NSString
            let dAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: SottoTheme.secondaryLabelColor,
            ]
            let dSize = weekday.size(withAttributes: dAttrs)
            weekday.draw(at: NSPoint(x: x + (barW - dSize.width) / 2, y: 0), withAttributes: dAttrs)
        }
    }
}

/// Trend bar chart for the history stats card: like BarChartView, but built
/// for arbitrary bucket counts — sparse x labels and the value called out only
/// on the tallest bar, so 30- or 52-bar ranges stay readable.
private final class TrendChartView: NSView {
    struct Bucket { let label: String; let value: Int }
    var buckets: [Bucket] = [] { didSet { needsDisplay = true } }

    private let labelH: CGFloat = 14
    private let valueH: CGFloat = 13

    override func draw(_ dirtyRect: NSRect) {
        guard !buckets.isEmpty, bounds.width > 10 else { return }
        let maxCount = max(buckets.map { $0.value }.max() ?? 1, 1)
        let chartH = bounds.height - labelH - valueH

        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: labelH - 1, width: bounds.width, height: 1).fill()

        guard let gradient = NSGradient(
            starting: SottoTheme.workspaceAccent.withAlphaComponent(0.58),
            ending: SottoTheme.workspaceAccent
        ) else { return }

        let n = buckets.count
        let gap = min(6, max(1.5, bounds.width / CGFloat(n) * 0.22))
        let barW = max((bounds.width - gap * CGFloat(n - 1)) / CGFloat(n), 1)
        let radius = min(3, barW / 2)
        // Aim for x labels at least ~34 pt apart, whatever the bucket count.
        let labelStep = max(1, Int((CGFloat(n) * 34 / bounds.width).rounded(.up)))
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: SottoTheme.secondaryLabelColor,
        ]

        var peakDrawn = false
        for (i, b) in buckets.enumerated() {
            let x = CGFloat(i) * (barW + gap)
            let frac = CGFloat(b.value) / CGFloat(maxCount)
            let h = max(chartH * frac, b.value > 0 ? 3 : 0)
            if b.value > 0 {
                let rect = NSRect(x: x, y: labelH, width: barW, height: h)
                gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius),
                              angle: 90)
            }
            if !peakDrawn && b.value == maxCount && b.value > 0 {
                peakDrawn = true
                let value = "\(b.value)" as NSString
                let vAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                    .foregroundColor: SottoTheme.workspaceAccent,
                ]
                let vSize = value.size(withAttributes: vAttrs)
                let vx = min(max(x + (barW - vSize.width) / 2, 0), bounds.width - vSize.width)
                value.draw(at: NSPoint(x: vx, y: min(labelH + h + 2, bounds.height - vSize.height)),
                           withAttributes: vAttrs)
            }
            if i % labelStep == 0 {
                let s = b.label as NSString
                let size = s.size(withAttributes: labelAttrs)
                let lx = min(max(x + (barW - size.width) / 2, 0), bounds.width - size.width)
                s.draw(at: NSPoint(x: lx, y: 0), withAttributes: labelAttrs)
            }
        }
    }
}

/// GitHub-style year activity heatmap: 53 columns of weeks, Sunday on top,
/// month labels above, 一/三/五 on the left. Cell brightness follows the
/// day's dictation count relative to the year's max.
private final class HeatmapView: NSView {
    var days: [DayStats] = [] { didSet { needsDisplay = true } }

    private let topH: CGFloat = 16
    private let leftW: CGFloat = 24

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: days[0].day) - 1  // 0 = Sunday
        let cols = (firstWeekday + days.count + 6) / 7
        let cell = min((bounds.width - leftW) / CGFloat(cols), (bounds.height - topH) / 7)
        let gap = max(cell * 0.18, 1.5)
        let side = max(cell - gap, 2)
        let maxCount = max(days.map { $0.count }.max() ?? 1, 1)
        let gridTop = bounds.height - topH
        let alphas: [CGFloat] = [0.22, 0.42, 0.66, 0.95]

        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "M月"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: SottoTheme.secondaryLabelColor,
        ]

        for (i, day) in days.enumerated() {
            let idx = i + firstWeekday
            let col = idx / 7
            let row = idx % 7
            let x = leftW + CGFloat(col) * cell
            let y = gridTop - CGFloat(row + 1) * cell + gap / 2
            if day.count == 0 {
                NSColor.white.withAlphaComponent(0.05).setFill()
            } else {
                let level = min(4, max(1, Int((Double(day.count) / Double(maxCount) * 4).rounded(.up))))
                SottoTheme.workspaceAccent.withAlphaComponent(alphas[level - 1]).setFill()
            }
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: side, height: side),
                         xRadius: 2, yRadius: 2).fill()

            if cal.component(.day, from: day.day) == 1 {
                (monthFmt.string(from: day.day) as NSString)
                    .draw(at: NSPoint(x: x, y: gridTop + 2), withAttributes: labelAttrs)
            }
        }

        for (row, name) in [(1, "一"), (3, "三"), (5, "五")] {
            let s = name as NSString
            let size = s.size(withAttributes: labelAttrs)
            let y = gridTop - CGFloat(row + 1) * cell + (cell - size.height) / 2
            s.draw(at: NSPoint(x: 0, y: y), withAttributes: labelAttrs)
        }
    }
}
