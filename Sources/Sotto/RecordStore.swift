import Foundation

/// One dictation event: both transcription stages. Audio is never persisted —
/// the temp WAV only lives long enough to be transcribed.
struct DictationRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let durationSeconds: Double
    let rawText: String        // raw ASR output
    let refinedText: String    // after LLM refinement (== rawText if refine off/failed)
    /// User's manual correction, the ground truth for the data flywheel. nil
    /// until the user fixes the record. Optional so old history.json still decodes.
    var correctedText: String? = nil

    /// Best available text: the human correction when present, else the refined text.
    var displayText: String {
        (correctedText?.isEmpty == false) ? correctedText! : refinedText
    }

    /// Whether the user has verified/fixed this record (it becomes training data).
    var isCorrected: Bool { correctedText?.isEmpty == false }

    /// Non-whitespace character count of the final (best) text.
    var charCount: Int {
        displayText.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    /// Characters per minute for this utterance.
    var charsPerMinute: Double {
        guard durationSeconds > 0.1 else { return 0 }
        return Double(charCount) / (durationSeconds / 60.0)
    }
}

/// Daily rollup used by the dashboard.
struct DayStats {
    let day: Date          // start of day
    let count: Int         // number of dictations
    let chars: Int         // total characters
    let seconds: Double    // total spoken duration
    var charsPerMinute: Double { seconds > 0.1 ? Double(chars) / (seconds / 60.0) : 0 }
}

/// Persists dictation history as JSON and computes the statistics shown in the
/// dashboard. All file I/O happens under `~/Library/Application Support/Sotto/`.
final class RecordStore {
    static let shared = RecordStore()

    /// Guards `records`: all reads/writes of the array go through this queue.
    private let queue = DispatchQueue(label: "com.chunyoupeng.Sotto.records")
    /// Disk writes happen here so `add` never blocks the caller on file I/O.
    private let ioQueue = DispatchQueue(label: "com.chunyoupeng.Sotto.records.io", qos: .utility)
    private var records: [DictationRecord] = []

    let baseDir: URL
    /// Where saved audio used to live; only touched to clean up legacy files.
    private let legacyAudioDir: URL
    private let jsonURL: URL

    /// Designated initializer, internal so tests can point a store at a temp dir.
    init(baseDir: URL) {
        let fm = FileManager.default
        self.baseDir = baseDir
        legacyAudioDir = baseDir.appendingPathComponent("audio", isDirectory: true)
        jsonURL = baseDir.appendingPathComponent("history.json")
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        load()
    }

    private convenience init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("Sotto", isDirectory: true)

        // One-time migration from the old "VoiceInput" folder name to "Sotto".
        let legacy = support.appendingPathComponent("VoiceInput", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: base.path) {
            try? fm.moveItem(at: legacy, to: base)
        }
        self.init(baseDir: base)
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode([DictationRecord].self, from: data) {
            records = decoded
        } else {
            // Corrupt history: keep the bytes for post-mortem instead of
            // silently overwriting them on the next dictation.
            let backup = baseDir.appendingPathComponent("history.corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: jsonURL, to: backup)
            SottoLog.log("RecordStore", "history.json unreadable; moved to \(backup.lastPathComponent)")
        }
    }

    /// Thread-safe copy of all records.
    private func snapshot() -> [DictationRecord] {
        queue.sync { records }
    }

    /// Serialize the current records to disk on the background I/O queue.
    private func persistAsync() {
        let snap = snapshot()
        ioQueue.async { [jsonURL] in
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted]
            if let data = try? enc.encode(snap) {
                try? data.write(to: jsonURL, options: .atomic)
            }
        }
    }

    /// Add a dictation (text only; the caller owns the temp WAV's cleanup).
    func add(rawText: String, refinedText: String, duration: TimeInterval) {
        let record = DictationRecord(
            id: UUID().uuidString, date: Date(), durationSeconds: duration,
            rawText: rawText, refinedText: refinedText)
        queue.sync { records.append(record) }
        persistAsync()
    }

    /// Most-recent-first.
    func recent(limit: Int = 200) -> [DictationRecord] {
        Array(snapshot().sorted { $0.date > $1.date }.prefix(limit))
    }

    func clearAll() {
        queue.sync { records.removeAll() }
        // Also drop any audio saved by older versions of the app.
        try? FileManager.default.removeItem(at: legacyAudioDir)
        persistAsync()
    }

    /// Delete a single record (history detail pane's 删除).
    func remove(id: String) {
        queue.sync { records.removeAll { $0.id == id } }
        persistAsync()
    }

    // MARK: - Editing (data flywheel)

    /// Store (or clear) the user's manual correction for a record. An empty or
    /// whitespace-only string, or restoring the original refined result,
    /// clears the correction.
    func setCorrection(id: String, correctedText: String?) {
        var retractedPair: (before: String, after: String)?
        var learningPair: (before: String, after: String)?
        queue.sync {
            guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
            let clean = correctedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldCorrection = records[idx].correctedText?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let newCorrection = (clean?.isEmpty == false && clean != records[idx].refinedText)
                ? clean : nil
            guard oldCorrection != newCorrection else { return }

            if let oldCorrection, !oldCorrection.isEmpty {
                retractedPair = (records[idx].refinedText, oldCorrection)
            }
            if let newCorrection {
                learningPair = (records[idx].refinedText, newCorrection)
            }
            records[idx].correctedText = newCorrection
        }
        if let pair = retractedPair {
            PersonalizationStore.retractCorrection(before: pair.before, after: pair.after)
        }
        if let pair = learningPair {
            PersonalizationStore.observeCorrection(before: pair.before, after: pair.after)
        }
        persistAsync()
    }

    // MARK: - Stats

    func todayStats() -> DayStats {
        stats(forDay: Date())
    }

    func stats(forDay date: Date) -> DayStats {
        Self.stats(forDay: date, in: snapshot())
    }

    private static func stats(forDay date: Date, in records: [DictationRecord]) -> DayStats {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let todays = records.filter { cal.isDate($0.date, inSameDayAs: date) }
        let chars = todays.reduce(0) { $0 + $1.charCount }
        let secs = todays.reduce(0.0) { $0 + $1.durationSeconds }
        return DayStats(day: dayStart, count: todays.count, chars: chars, seconds: secs)
    }

    /// Stats for the last `days` days, oldest-first, including empty days.
    func lastDays(_ days: Int) -> [DayStats] {
        let snap = snapshot()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Self.stats(forDay: d, in: snap)
        }
    }

    /// Same rollup as `lastDays`, but bucketed in a single pass over the
    /// records — used by the year heatmap, where 365 × `stats(forDay:)`
    /// filter passes would be wasteful.
    func dailyStats(lastDays days: Int) -> [DayStats] {
        let snap = snapshot()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var buckets: [Date: (count: Int, chars: Int, secs: Double)] = [:]
        for r in snap where r.date >= start {
            let d = cal.startOfDay(for: r.date)
            var b = buckets[d] ?? (0, 0, 0)
            b.count += 1
            b.chars += r.charCount
            b.secs += r.durationSeconds
            buckets[d] = b
        }
        return (0..<days).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let b = buckets[d] ?? (0, 0, 0)
            return DayStats(day: d, count: b.count, chars: b.chars, seconds: b.secs)
        }
    }

    var totalChars: Int { snapshot().reduce(0) { $0 + $1.charCount } }
    var totalCount: Int { queue.sync { records.count } }
}
