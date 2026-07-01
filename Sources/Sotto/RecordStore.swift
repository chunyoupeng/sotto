import Foundation

/// One dictation event: the captured audio plus both transcription stages.
struct DictationRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let durationSeconds: Double
    let rawText: String        // raw ASR output
    let refinedText: String    // after LLM refinement (== rawText if refine off/failed)
    let audioFileName: String? // relative to the store's audio directory, nil if not saved
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

/// Persists dictation history as JSON plus the raw audio files, and computes
/// the statistics shown in the dashboard. All file I/O happens under
/// `~/Library/Application Support/Sotto/`.
final class RecordStore {
    static let shared = RecordStore()

    private let queue = DispatchQueue(label: "com.chunyoupeng.Sotto.records")
    private(set) var records: [DictationRecord] = []

    let baseDir: URL
    let audioDir: URL
    private let jsonURL: URL

    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("Sotto", isDirectory: true)

        // One-time migration from the old "VoiceInput" folder name to "Sotto".
        let legacy = support.appendingPathComponent("VoiceInput", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: baseDir.path) {
            try? fm.moveItem(at: legacy, to: baseDir)
        }

        audioDir = baseDir.appendingPathComponent("audio", isDirectory: true)
        jsonURL = baseDir.appendingPathComponent("history.json")
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        records = (try? dec.decode([DictationRecord].self, from: data)) ?? []
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(records) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    /// Add a dictation. If `tempAudioURL` is given and audio saving is enabled,
    /// the file is moved into the store; otherwise it is left untouched (caller
    /// owns cleanup of temp files when audio is not saved).
    func add(rawText: String, refinedText: String, duration: TimeInterval,
             tempAudioURL: URL?) {
        let id = UUID().uuidString
        var savedName: String? = nil

        if AppSettings.saveAudio, let src = tempAudioURL,
           FileManager.default.fileExists(atPath: src.path) {
            let name = "\(id).wav"
            let dest = audioDir.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                savedName = name
            } catch {
                savedName = nil
            }
        }

        let record = DictationRecord(
            id: id, date: Date(), durationSeconds: duration,
            rawText: rawText, refinedText: refinedText, audioFileName: savedName)

        queue.sync {
            records.append(record)
            persist()
        }
    }

    func audioURL(for record: DictationRecord) -> URL? {
        guard let name = record.audioFileName else { return nil }
        let url = audioDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Most-recent-first.
    func recent(limit: Int = 200) -> [DictationRecord] {
        Array(records.sorted { $0.date > $1.date }.prefix(limit))
    }

    func clearAll() {
        queue.sync {
            for r in records {
                if let url = audioURL(for: r) { try? FileManager.default.removeItem(at: url) }
            }
            records.removeAll()
            persist()
        }
    }

    // MARK: - Editing (data flywheel)

    /// Store (or clear) the user's manual correction for a record. An empty or
    /// whitespace-only string clears the correction.
    func setCorrection(id: String, correctedText: String?) {
        queue.sync {
            guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
            let clean = correctedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            records[idx].correctedText = (clean?.isEmpty == false) ? clean : nil
            persist()
        }
    }

    /// Records the user has corrected — the training set.
    var correctedCount: Int { records.reduce(0) { $0 + ($1.isCorrected ? 1 : 0) } }

    /// Export corrected records as JSON Lines suitable for ASR fine-tuning:
    /// one object per line with the raw ASR output, the human-corrected target,
    /// and the absolute audio path when available. Returns the number written.
    @discardableResult
    func exportTrainingData(to url: URL) throws -> Int {
        let samples = records
            .filter { $0.isCorrected }
            .sorted { $0.date < $1.date }
        var lines: [String] = []
        for r in samples {
            var obj: [String: Any] = ["raw": r.rawText, "text": r.correctedText ?? r.refinedText]
            if let name = r.audioFileName {
                obj["audio"] = audioDir.appendingPathComponent(name).path
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return lines.count
    }

    // MARK: - Stats

    func todayStats() -> DayStats {
        stats(forDay: Date())
    }

    func stats(forDay date: Date) -> DayStats {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let todays = records.filter { cal.isDate($0.date, inSameDayAs: date) }
        let chars = todays.reduce(0) { $0 + $1.charCount }
        let secs = todays.reduce(0.0) { $0 + $1.durationSeconds }
        return DayStats(day: dayStart, count: todays.count, chars: chars, seconds: secs)
    }

    /// Stats for the last `days` days, oldest-first, including empty days.
    func lastDays(_ days: Int) -> [DayStats] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return stats(forDay: d)
        }
    }

    var totalChars: Int { records.reduce(0) { $0 + $1.charCount } }
    var totalCount: Int { records.count }
}
