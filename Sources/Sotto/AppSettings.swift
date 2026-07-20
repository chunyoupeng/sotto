import Foundation
import CoreGraphics

/// Centralized settings for triggers, the ASR engine, and history capture.
///
/// Backed by `~/.sotto/config.json` (see `SottoConfig`) — the file is the single
/// source of truth. LLM settings live in `LLMRefiner`; the recognition language
/// lives in `localeCode` below.
enum AppSettings {
    // MARK: - Triggers

    /// Press-and-hold key. Default: Fn.
    static var holdHotkey: Hotkey {
        get { SottoConfig.codable("holdHotkey", as: Hotkey.self) ?? .fn }
        set { SottoConfig.setCodable(newValue, forKey: "holdHotkey") }
    }

    static var holdEnabled: Bool {
        get { SottoConfig.bool("holdEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "holdEnabled") }
    }

    /// Optional separate toggle key (tap to start, tap to stop). Default: none.
    static var toggleHotkey: Hotkey? {
        get { SottoConfig.codable("toggleHotkey", as: Hotkey.self) }
        set {
            if let v = newValue { SottoConfig.setCodable(v, forKey: "toggleHotkey") }
            else { SottoConfig.set(nil, forKey: "toggleHotkey") }
        }
    }

    static var toggleEnabled: Bool {
        get { SottoConfig.bool("toggleEnabled") ?? false }
        set { SottoConfig.set(newValue, forKey: "toggleEnabled") }
    }

    /// Global hotkey to summon the dashboard. Default: ⌃⌘D.
    static var dashboardHotkey: Hotkey {
        get {
            SottoConfig.codable("dashboardHotkey", as: Hotkey.self)
                ?? Hotkey(keyCode: 2,  // D
                          modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue)
        }
        set { SottoConfig.setCodable(newValue, forKey: "dashboardHotkey") }
    }

    // Off by default: the dashboard is reachable from the menu-bar icon, so a
    // global hotkey isn't needed and only risks shadowing a normal key.
    static var dashboardEnabled: Bool {
        get { SottoConfig.bool("dashboardEnabled") ?? false }
        set { SottoConfig.set(newValue, forKey: "dashboardEnabled") }
    }

    /// Hold-style translate chord. Default: fn⇧ (Typeless-style).
    static var translateHotkey: Hotkey {
        get {
            SottoConfig.codable("translateHotkey", as: Hotkey.self)
                ?? Hotkey(keyCode: 56, modifiers: Hotkey.fnModifier)  // fn + L⇧
        }
        set { SottoConfig.setCodable(newValue, forKey: "translateHotkey") }
    }

    static var translateEnabled: Bool {
        get { SottoConfig.bool("translateEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "translateEnabled") }
    }

    /// Hold-style QA key. Default: fn Space (Typeless-style).
    static var qaHotkey: Hotkey {
        get {
            SottoConfig.codable("qaHotkey", as: Hotkey.self)
                ?? Hotkey(keyCode: 49, modifiers: Hotkey.fnModifier)  // fn + Space
        }
        set { SottoConfig.setCodable(newValue, forKey: "qaHotkey") }
    }

    static var qaEnabled: Bool {
        get { SottoConfig.bool("qaEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "qaEnabled") }
    }

    /// Global hotkey that reopens the most recent dictation in the correction
    /// editor, so a bad result can be fixed without hunting through the
    /// dashboard. Default: ⌃⌘E.
    static var editLastHotkey: Hotkey {
        get {
            SottoConfig.codable("editLastHotkey", as: Hotkey.self)
                ?? Hotkey(keyCode: 14,  // E
                          modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue)
        }
        set { SottoConfig.setCodable(newValue, forKey: "editLastHotkey") }
    }

    static var editLastEnabled: Bool {
        get { SottoConfig.bool("editLastEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "editLastEnabled") }
    }

    /// When holding the hold-key, a quick tap (< `tapThreshold`) locks recording
    /// so it continues until the key is tapped again (Doubao-style). A real hold
    /// stops on release (push-to-talk).
    static var smartTapToLock: Bool {
        get { SottoConfig.bool("smartTapToLock") ?? true }
        set { SottoConfig.set(newValue, forKey: "smartTapToLock") }
    }

    static var tapThreshold: Double {
        get { SottoConfig.double("tapThreshold") ?? 0.4 }
        set { SottoConfig.set(newValue, forKey: "tapThreshold") }
    }

    // MARK: - History capture

    static var saveHistory: Bool {
        get { SottoConfig.bool("saveHistory") ?? true }
        set { SottoConfig.set(newValue, forKey: "saveHistory") }
    }

    // MARK: - Intelligent writing

    /// Feed a compact, locally learned style profile into refine requests.
    static var personalizationEnabled: Bool {
        get { SottoConfig.bool("personalizationEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "personalizationEnabled") }
    }

    /// Derive a conservative tone instruction from the frontmost application.
    static var appAwareToneEnabled: Bool {
        get { SottoConfig.bool("appAwareToneEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "appAwareToneEnabled") }
    }

    /// Let the QA hotkey use selected text as rewrite/question context.
    static var selectionAssistantEnabled: Bool {
        get { SottoConfig.bool("selectionAssistantEnabled") ?? true }
        set { SottoConfig.set(newValue, forKey: "selectionAssistantEnabled") }
    }

    /// Save conservative correction diffs as pending dictionary suggestions.
    static var autoLearnDictionary: Bool {
        get { SottoConfig.bool("autoLearnDictionary") ?? true }
        set { SottoConfig.set(newValue, forKey: "autoLearnDictionary") }
    }

    /// Apply extra input gain before writing the WAV for quiet/whispered speech.
    static var whisperModeEnabled: Bool {
        get { SottoConfig.bool("whisperModeEnabled") ?? false }
        set { SottoConfig.set(newValue, forKey: "whisperModeEnabled") }
    }

    /// Mute the system output device while the mic is recording (restored on
    /// stop), so background music/video never bleeds into the dictation.
    static var muteWhileRecording: Bool {
        get { SottoConfig.bool("muteWhileRecording") ?? true }
        set { SottoConfig.set(newValue, forKey: "muteWhileRecording") }
    }

    // MARK: - Recognition language

    /// Empty = let the multilingual ASR model detect the spoken language.
    static var localeCode: String {
        get { SottoConfig.string("selectedLocaleCode") ?? "zh-CN" }
        set { SottoConfig.set(newValue, forKey: "selectedLocaleCode") }
    }

    // MARK: - ASR engine

    /// Recognition backend: local MLX sidecar or a remote OpenAI-compatible
    /// `/audio/transcriptions` endpoint.
    enum ASRBackend: String {
        case local
        case openAI = "openai"
    }

    static var asrBackend: ASRBackend {
        get { SottoConfig.string("asrBackend").flatMap(ASRBackend.init(rawValue:)) ?? .local }
        set { SottoConfig.set(newValue.rawValue, forKey: "asrBackend") }
    }

    /// Base URL of the OpenAI-compatible ASR service (e.g. https://api.openai.com/v1).
    static var asrAPIBaseURL: String {
        get { SottoConfig.string("asrAPIBaseURL") ?? "" }
        set { SottoConfig.set(newValue, forKey: "asrAPIBaseURL") }
    }

    static var asrAPIKey: String {
        get { SottoConfig.string("asrAPIKey") ?? "" }
        set { SottoConfig.set(newValue, forKey: "asrAPIKey") }
    }

    /// Model name sent to the remote endpoint (e.g. whisper-1).
    static var asrAPIModel: String {
        get { SottoConfig.string("asrAPIModel") ?? "" }
        set { SottoConfig.set(newValue, forKey: "asrAPIModel") }
    }

    /// Empty = auto (use the bundled frozen engine; only needed for dev override).
    static var asrPythonPath: String {
        get { SottoConfig.string("asrPythonPath") ?? "" }
        set { SottoConfig.set(newValue, forKey: "asrPythonPath") }
    }

    /// Empty = auto (resolve managed model dir, then dev cache).
    static var asrModelPath: String {
        get { SottoConfig.string("asrModelPath") ?? "" }
        set { SottoConfig.set(newValue, forKey: "asrModelPath") }
    }

    /// Managed model directory — where models live under `~/.sotto/models`.
    static var managedModelDir: URL { SottoConfig.modelsDir }

    /// Default model folder name expected inside the managed dir / dev cache.
    static let defaultModelName = "Qwen3-ASR-0.6B-8bit"

    /// Default model location in the user-owned Sotto home.
    static var defaultManagedModelURL: URL {
        managedModelDir.appendingPathComponent(defaultModelName, isDirectory: true)
    }

    // MARK: - Dev fallbacks

    /// Repo root on the machine this binary was built on, derived from the
    /// source location at compile time. Only meaningful for local dev builds
    /// (`swift run` before `make engine`/`make model`); shipped apps resolve the
    /// bundled engine and managed model first and never reach these paths.
    static let devRepoRoot = URL(fileURLWithPath: #filePath)  // …/Sources/Sotto/AppSettings.swift
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var devPythonPath: String {
        devRepoRoot.appendingPathComponent(".venv/bin/python3").path
    }

    /// ModelScope's local cache location for the default model, if the developer
    /// has downloaded it there.
    static var devModelPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0___6B-8bit")
            .path
    }
}
