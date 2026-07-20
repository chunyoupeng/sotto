import Foundation

struct DictionarySuggestion: Codable, Equatable, Identifiable {
    var id: String { "\(source)→\(replacement)" }
    let source: String
    let replacement: String
    var occurrences: Int
}

struct WritingProfile: Codable, Equatable {
    var correctionCount = 0
    var conciseVotes = 0
    var structuredVotes = 0

    var promptSummary: String? {
        guard correctionCount > 0 else { return nil }
        var traits: [String] = []
        if conciseVotes * 2 >= correctionCount {
            traits.append("用户经常把结果改得更简洁，优先短句并删除套话")
        }
        if structuredVotes * 3 >= correctionCount {
            traits.append("用户在多事项内容中偏好列表和清晰分段")
        }
        traits.append("这些偏好只能调整表达方式，不能改变事实或补充内容")
        return traits.joined(separator: "；")
    }
}

/// Local-only personalization derived from explicit human corrections.
/// Nothing here uploads history: each request receives only a compact style
/// summary and accepted dictionary entries.
enum PersonalizationStore {
    private static let suggestionsKey = "dictionarySuggestions"
    private static let profileKey = "writingProfile"

    static var suggestions: [DictionarySuggestion] {
        SottoConfig.codable(suggestionsKey, as: [DictionarySuggestion].self) ?? []
    }

    static var profile: WritingProfile {
        SottoConfig.codable(profileKey, as: WritingProfile.self) ?? WritingProfile()
    }

    static var promptSummary: String? {
        guard AppSettings.personalizationEnabled else { return nil }
        return profile.promptSummary
    }

    /// Learn only from text the user explicitly saved as correct. Vocabulary
    /// candidates remain pending until accepted in Dictionary, which prevents a
    /// one-off rewrite from silently poisoning ASR hotwords.
    static func observeCorrection(before: String, after: String) {
        let old = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = after.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }

        var p = profile
        p.correctionCount += 1
        if Double(new.count) < Double(old.count) * 0.85 { p.conciseVotes += 1 }
        if isStructured(new) && !isStructured(old) { p.structuredVotes += 1 }
        SottoConfig.setCodable(p, forKey: profileKey)

        guard AppSettings.autoLearnDictionary,
              let candidate = correctionCandidate(before: old, after: new) else { return }
        var pending = suggestions
        if let index = pending.firstIndex(where: {
            $0.source == candidate.source && $0.replacement == candidate.replacement
        }) {
            pending[index].occurrences += 1
        } else {
            pending.insert(candidate, at: 0)
        }
        SottoConfig.setCodable(Array(pending.prefix(30)), forKey: suggestionsKey)
    }

    /// Remove one pending occurrence when a saved correction is replaced or
    /// reset, so Dictionary never keeps a stale diff from an earlier edit.
    static func retractCorrection(before: String, after: String) {
        guard let candidate = correctionCandidate(before: before, after: after) else { return }
        var pending = suggestions
        guard let index = pending.firstIndex(where: { $0.id == candidate.id }) else { return }
        if pending[index].occurrences > 1 {
            pending[index].occurrences -= 1
        } else {
            pending.remove(at: index)
        }
        SottoConfig.setCodable(pending, forKey: suggestionsKey)
    }

    static func acceptSuggestion(id: String) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        var raw = SottoConfig.readHotwordsRaw()
        let active = Set(SottoConfig.readHotwords().map { $0.lowercased() })
        if !active.contains(suggestion.replacement.lowercased()) {
            if !raw.hasSuffix("\n") { raw += "\n" }
            raw += suggestion.replacement + "\n"
            SottoConfig.writeHotwords(raw)
        }
        dismissSuggestion(id: id)
    }

    static func dismissSuggestion(id: String) {
        let remaining = suggestions.filter { $0.id != id }
        SottoConfig.setCodable(remaining, forKey: suggestionsKey)
    }

    static func correctionCandidate(before: String, after: String) -> DictionarySuggestion? {
        let oldChars = Array(before)
        let newChars = Array(after)
        var prefix = 0
        while prefix < min(oldChars.count, newChars.count), oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(oldChars.count - prefix, newChars.count - prefix),
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        // Widen the char-level diff to whole alphabetic words: "novus" →
        // "novels" must learn the full pair, not the fragment "u" → "el".
        // CJK chars don't join, so 中文 corrections keep their compact diff.
        while prefix > 0, joinsWord(oldChars[prefix - 1]) {
            prefix -= 1
        }
        while suffix > 0, joinsWord(oldChars[oldChars.count - suffix]) {
            suffix -= 1
        }
        let oldEnd = oldChars.count - suffix
        let newEnd = newChars.count - suffix
        let source = String(oldChars[prefix..<oldEnd]).trimmingCharacters(in: trimSet)
        let replacement = String(newChars[prefix..<newEnd]).trimmingCharacters(in: trimSet)
        guard !source.isEmpty, !replacement.isEmpty, source != replacement,
              replacement.count >= 2, replacement.count <= 48,
              replacement.split(whereSeparator: \Character.isWhitespace).count <= 4,
              !replacement.contains("\n") else { return nil }
        return DictionarySuggestion(source: source, replacement: replacement, occurrences: 1)
    }

    private static let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    /// True for characters that spell out a single word (Latin letters, digits,
    /// accents…). Ideographic scripts write words without separators, so their
    /// characters intentionally return false.
    private static func joinsWord(_ ch: Character) -> Bool {
        guard ch.isLetter || ch.isNumber else { return false }
        return !ch.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x2E80...0x9FFF).contains(v)      // CJK radicals, kana, ideographs
                || (0xAC00...0xD7FF).contains(v)      // Hangul syllables
                || (0xF900...0xFAFF).contains(v)      // CJK compatibility ideographs
                || (0x20000...0x2FA1F).contains(v)    // CJK extensions
        }
    }

    private static func isStructured(_ text: String) -> Bool {
        text.contains("\n-") || text.contains("\n•") ||
            text.range(of: "(?m)^\\s*\\d+[.、)]\\s*", options: .regularExpression) != nil
    }
}

/// Resolves a compact tone instruction from the active application. This is a
/// deterministic local policy, not a claim that every app in a category should
/// always be rewritten; the prompt keeps meaning-preservation as the hard rule.
enum AppToneResolver {
    static func instruction(for appName: String?) -> String? {
        guard AppSettings.appAwareToneEnabled,
              let app = PromptComposer.sanitizedAppName(appName)?.lowercased() else { return nil }
        if ["mail", "outlook", "gmail", "spark"].contains(where: app.contains) {
            return "邮件场景：表达完整、自然、适度正式；不要擅自添加称呼、落款或承诺"
        }
        if ["slack", "discord", "微信", "messages", "telegram", "teams"].contains(where: app.contains) {
            return "即时沟通场景：简洁、自然、像真人聊天；避免公文腔和不必要标题"
        }
        if ["xcode", "cursor", "visual studio code", "terminal", "iterm", "warp"].contains(where: app.contains) {
            return "开发场景：保留代码、变量、命令、路径、版本号和 Markdown，不翻译技术标识符"
        }
        if ["notion", "obsidian", "notes", "备忘录", "word", "pages"].contains(where: app.contains) {
            return "文档场景：需要时分段或列点，但短句不要过度结构化"
        }
        return "通用场景：保持原说话人的语气和详略，不套用固定公文风格"
    }
}
