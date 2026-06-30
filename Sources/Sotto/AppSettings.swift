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

    static var saveAudio: Bool {
        get { SottoConfig.bool("saveAudio") ?? true }
        set { SottoConfig.set(newValue, forKey: "saveAudio") }
    }

    // MARK: - Recognition language

    /// Empty = follow the system locale.
    static var localeCode: String {
        get { SottoConfig.string("selectedLocaleCode") ?? "zh-CN" }
        set { SottoConfig.set(newValue, forKey: "selectedLocaleCode") }
    }

    // MARK: - ASR engine

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

    /// Dev-only fallbacks (this machine), used when nothing else resolves.
    static let devPythonPath = "/Users/pengchunyou/Projects/sotto/.venv/bin/python3"
    static let devModelPath = "/Users/pengchunyou/.cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0___6B-8bit"
}
