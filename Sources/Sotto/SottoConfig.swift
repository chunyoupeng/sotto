import CoreGraphics
import Foundation

/// The app's home directory at `~/.sotto`.
///
/// Everything user-owned lives here, so the app is self-contained and easy to
/// back up or inspect:
///
///   ~/.sotto/
///   ├── config.json     structured settings (the single source of truth)
///   ├── prompt.txt      LLM refine system prompt (plain text, editable)
///   └── models/         ASR model storage
///
/// On first launch, any pre-existing `UserDefaults` values are migrated into
/// `config.json` (and the prompt into `prompt.txt`) so nothing is lost. On every
/// launch, any built-in default that is still missing from the file is filled in
/// (never overwriting a value the user already set), so the file stays the
/// complete source of truth. `UserDefaults` is otherwise left untouched.
enum SottoConfig {
    static let homeDir: URL = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent(".sotto", isDirectory: true)
    static let configURL = homeDir.appendingPathComponent("config.json")
    static let promptURL = homeDir.appendingPathComponent("prompt.txt")
    static let modelsDir = homeDir.appendingPathComponent("models", isDirectory: true)

    private static let lock = NSLock()
    private static var cache: [String: Any] = load()

    // MARK: - Typed access

    /// Raw value for a key, or nil if unset.
    static func object(_ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    static func string(_ key: String) -> String? { object(key) as? String }

    static func bool(_ key: String) -> Bool? { object(key) as? Bool }

    /// Numeric value as Double (handles Int/Double/NSNumber in JSON).
    static func double(_ key: String) -> Double? {
        if let n = object(key) as? NSNumber { return n.doubleValue }
        if let d = object(key) as? Double { return d }
        if let i = object(key) as? Int { return Double(i) }
        return nil
    }

    /// Sets a value (nil removes the key) and persists to disk.
    static func set(_ value: Any?, forKey key: String) {
        lock.lock()
        if let v = value { cache[key] = v } else { cache.removeValue(forKey: key) }
        let snapshot = cache
        lock.unlock()
        persist(snapshot)
    }

    /// Stores a `Codable` value as a readable JSON object inside `config.json`.
    static func codable<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let obj = object(key) else { return nil }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func setCodable<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        set(obj, forKey: key)
    }

    // MARK: - Prompt file

    static func readPrompt() -> String {
        (try? String(contentsOf: promptURL, encoding: .utf8)) ?? ""
    }

    static func writePrompt(_ text: String) {
        try? FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try? text.write(to: promptURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Load / migrate / persist

    private static func load() -> [String: Any] {
        let fm = FileManager.default
        try? fm.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        var result: [String: Any] = [:]
        var needsPersist = false
        if let data = try? Data(contentsOf: configURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = obj
        } else {
            // First run: migrate any pre-existing UserDefaults values in.
            result = migrate(from: UserDefaults.standard)
            if result.isEmpty { result = defaults() }
            needsPersist = true
        }

        // Always fill in any missing built-in defaults so config.json stays the
        // complete source of truth — an existing file may predate a key being
        // added. Never overwrites a value the user (or migration) already set.
        for (k, v) in defaults() where result[k] == nil {
            result[k] = v
            needsPersist = true
        }
        if needsPersist { persist(result) }

        // The prompt file is independent of config.json: seed it whenever it's
        // missing, regardless of whether config.json already existed.
        if readPrompt().isEmpty {
            let existingPrompt = UserDefaults.standard.string(forKey: "llmSystemPrompt")
            writePrompt((existingPrompt?.isEmpty == false) ? existingPrompt! : LLMRefiner.defaultSystemPrompt)
        }

        linkDevModelIfNeeded()
        return result
    }

    /// One-time migration of the known `UserDefaults` keys into a config dict.
    private static func migrate(from d: UserDefaults) -> [String: Any] {
        var seed: [String: Any] = [:]
        let boolKeys = ["holdEnabled", "toggleEnabled", "dashboardEnabled",
                        "smartTapToLock", "saveHistory", "saveAudio", "llmEnabled"]
        let stringKeys = ["asrPythonPath", "asrModelPath", "selectedLocaleCode",
                          "llmAPIBaseURL", "llmAPIKey", "llmModel"]
        let doubleKeys = ["tapThreshold"]
        let hotkeyKeys = ["holdHotkey", "toggleHotkey", "dashboardHotkey"]

        for k in boolKeys { if let v = d.object(forKey: k) as? Bool { seed[k] = v } }
        for k in stringKeys { if let v = d.string(forKey: k) { seed[k] = v } }
        for k in doubleKeys { if d.object(forKey: k) != nil { seed[k] = d.double(forKey: k) } }
        for k in hotkeyKeys {
            if let data = d.data(forKey: k), let hk = Hotkey.decode(data),
               let jd = try? JSONEncoder().encode(hk),
               let jo = try? JSONSerialization.jsonObject(with: jd) {
                seed[k] = jo
            }
        }
        return seed
    }

    /// Built-in defaults used when nothing has ever been configured.
    private static func defaults() -> [String: Any] {
        var values: [String: Any] = [
            "holdEnabled": true,
            "toggleEnabled": false,
            "dashboardEnabled": true,
            "smartTapToLock": true,
            "tapThreshold": 0.4,
            "saveHistory": true,
            "saveAudio": true,
            "selectedLocaleCode": "zh-CN",
            "asrPythonPath": "",
            "asrModelPath": AppSettings.defaultManagedModelURL.path,
            "llmEnabled": false,
            "llmAPIBaseURL": LLMRefiner.defaultAPIBaseURL,
            "llmAPIKey": "",
            "llmModel": LLMRefiner.defaultModel,
        ]
        if let holdHotkey = jsonObject(Hotkey.fn) {
            values["holdHotkey"] = holdHotkey
        }
        if let dashboardHotkey = jsonObject(Hotkey(
            keyCode: 2,  // D
            modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
        )) {
            values["dashboardHotkey"] = dashboardHotkey
        }
        return values
    }

    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// On dev machines the model often lives in the modelscope cache; expose it
    /// inside `~/.sotto/models` via a symlink so the layout is consistent without
    /// copying gigabytes. No-op for end users (bundled model) or if already present.
    private static func linkDevModelIfNeeded() {
        let fm = FileManager.default
        let link = modelsDir.appendingPathComponent(AppSettings.defaultModelName)
        guard !fm.fileExists(atPath: link.path),
              fm.fileExists(atPath: AppSettings.devModelPath) else { return }
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: AppSettings.devModelPath)
    }

    private static func persist(_ snapshot: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
