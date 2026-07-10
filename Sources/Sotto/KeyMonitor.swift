import Cocoa

/// Global hotkey monitor backed by a CGEvent tap. Supports two independently
/// configurable hotkeys: a *hold* key (reports down/up) and a *toggle* key
/// (reports a single down per press). Each hotkey may be the Fn key, a bare
/// modifier key (e.g. Right ⌘), or a regular key with optional modifiers.
final class KeyMonitor {
    /// Hold key transitions.
    var onHoldDown: (() -> Void)?
    var onHoldUp: (() -> Void)?
    /// Toggle key pressed once.
    var onToggleDown: (() -> Void)?
    /// Dashboard summon key pressed once.
    var onDashboardDown: (() -> Void)?
    /// Translate key transitions (hold-style, may be a fn+modifier chord).
    var onTranslateDown: (() -> Void)?
    var onTranslateUp: (() -> Void)?
    /// QA key transitions (hold-style).
    var onQADown: (() -> Void)?
    var onQAUp: (() -> Void)?

    var holdHotkey: Hotkey? = .fn
    var holdEnabled = true
    var toggleHotkey: Hotkey? = nil
    var toggleEnabled = false
    var dashboardHotkey: Hotkey? = nil
    var translateHotkey: Hotkey? = nil
    var qaHotkey: Hotkey? = nil

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Pressed state to debounce repeated flagsChanged / key autorepeat.
    private var holdActive = false
    private var toggleActive = false
    private var dashboardActive = false
    private var translateActive = false
    private var qaActive = false

    /// Reconfigure from current `AppSettings`.
    func reload() {
        holdHotkey = AppSettings.holdEnabled ? AppSettings.holdHotkey : nil
        holdEnabled = AppSettings.holdEnabled
        toggleHotkey = AppSettings.toggleEnabled ? AppSettings.toggleHotkey : nil
        toggleEnabled = AppSettings.toggleEnabled
        dashboardHotkey = AppSettings.dashboardEnabled ? AppSettings.dashboardHotkey : nil
        translateHotkey = AppSettings.translateEnabled ? AppSettings.translateHotkey : nil
        qaHotkey = AppSettings.qaEnabled ? AppSettings.qaHotkey : nil
    }

    /// Start monitoring. Returns false if accessibility permission is missing.
    func start() -> Bool {
        reload()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue))
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        holdActive = false
        toggleActive = false
        dashboardActive = false
        translateActive = false
        qaActive = false
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Translate and QA are evaluated BEFORE the hold key: their default
        // chords share Fn with the default hold key, and the hold branch
        // swallows (`return nil`) every flagsChanged while Fn is down — placed
        // after it, the chord's second key would never be seen.

        // A translate/QA chord transition claims the event: when the hold key is
        // a bare modifier that is a subset of the chord (e.g. hold = R⌃, QA =
        // R⌃R⌘), the flagsChanged that completes the chord also carries the hold
        // key's own keycode — letting it double as a hold press would stop the
        // chord's session and instantly start a phantom dictation capture.
        var chordFired = false

        // --- Translate key (hold-style) ---
        if let tk = translateHotkey {
            if let (down, matched) = match(tk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !translateActive {
                        translateActive = true
                        chordFired = true
                        DispatchQueue.main.async { [weak self] in self?.onTranslateDown?() }
                        if shouldSuppress(tk) { return nil }
                    } else if !down && translateActive {
                        translateActive = false
                        chordFired = true
                        DispatchQueue.main.async { [weak self] in self?.onTranslateUp?() }
                        if shouldSuppress(tk) { return nil }
                    } else if down && shouldSuppress(tk) && !tk.isModifierKey {
                        return nil
                    }
                }
            }
        }

        // --- QA key (hold-style) ---
        if let qk = qaHotkey {
            if let (down, matched) = match(qk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !qaActive {
                        qaActive = true
                        chordFired = true
                        DispatchQueue.main.async { [weak self] in self?.onQADown?() }
                        if shouldSuppress(qk) { return nil }
                    } else if !down && qaActive {
                        qaActive = false
                        chordFired = true
                        DispatchQueue.main.async { [weak self] in self?.onQAUp?() }
                        if shouldSuppress(qk) { return nil }
                    } else if down && shouldSuppress(qk) && !qk.isModifierKey {
                        return nil
                    }
                }
            }
        }

        // --- Hold key ---
        if let hk = holdHotkey {
            if let (down, matched) = match(hk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !holdActive && !chordFired {
                        holdActive = true
                        DispatchQueue.main.async { [weak self] in self?.onHoldDown?() }
                        if shouldSuppress(hk) { return nil }
                    } else if !down && holdActive {
                        holdActive = false
                        DispatchQueue.main.async { [weak self] in self?.onHoldUp?() }
                        if shouldSuppress(hk) { return nil }
                    } else if down && shouldSuppress(hk) && !hk.isModifierKey {
                        // swallow autorepeat keyDowns for a held regular key
                        return nil
                    }
                }
            }
        }

        // --- Toggle key ---
        if let tk = toggleHotkey {
            if let (down, matched) = match(tk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !toggleActive && !chordFired {
                        toggleActive = true
                        DispatchQueue.main.async { [weak self] in self?.onToggleDown?() }
                        if shouldSuppress(tk) { return nil }
                    } else if !down && toggleActive {
                        toggleActive = false
                        if shouldSuppress(tk) { return nil }
                    } else if down && shouldSuppress(tk) && !tk.isModifierKey {
                        return nil
                    }
                }
            }
        }

        // --- Dashboard key ---
        if let dk = dashboardHotkey {
            if let (down, matched) = match(dk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !dashboardActive && !chordFired {
                        dashboardActive = true
                        DispatchQueue.main.async { [weak self] in self?.onDashboardDown?() }
                        if shouldSuppress(dk) { return nil }
                    } else if !down && dashboardActive {
                        dashboardActive = false
                        if shouldSuppress(dk) { return nil }
                    } else if down && shouldSuppress(dk) && !dk.isModifierKey {
                        return nil
                    }
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Returns `(isDown, matched)` if this event concerns the hotkey, else nil.
    private func match(_ hk: Hotkey, type: CGEventType, keyCode: Int, flags: CGEventFlags)
        -> (Bool, Bool)? {
        if hk.isFn {
            guard type == .flagsChanged else { return nil }
            return (flags.contains(.maskSecondaryFn), true)
        }
        if let modFlag = Hotkey.modifierFlag(forKeyCode: hk.keyCode) {
            guard type == .flagsChanged else { return nil }
            if hk.modifiers != 0 {
                // Modifier chord (fn⇧, ⌃⇧, …): evaluate on *any* flagsChanged
                // by flag state alone — the keys can land in either order,
                // and keying on the chord key's own keycode would miss the
                // "other key arrived second" ordering. Debounced by the
                // caller's active-state tracking. Matching is *exact* (no
                // extra modifiers) and, when the chord was recorded with
                // left/right identity, side-specific via the device bits.
                var required = hk.modifiers | modFlag.rawValue
                var relevant: UInt64 =
                    CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
                    CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue
                if required & Hotkey.fnModifier != 0 { relevant |= Hotkey.fnModifier }
                if hk.modifiers & Hotkey.allDeviceBits != 0 {
                    required |= Hotkey.deviceBit(forKeyCode: hk.keyCode) ?? 0
                    relevant |= Hotkey.allDeviceBits
                }
                return ((flags.rawValue & relevant) == required, true)
            }
            // Bare modifier key: a flagsChanged whose keycode is this modifier.
            guard keyCode == hk.keyCode else { return nil }
            return (flags.contains(modFlag), true)
        }
        // Regular key.
        guard keyCode == hk.keyCode else { return nil }
        switch type {
        case .keyDown:
            // Only claim this keystroke when the required modifiers are held.
            // Otherwise it's an ordinary press (e.g. a bare "d") that must pass
            // through untouched — claiming it here would swallow the key entirely.
            return modifiersMatch(hk.modifiers, flags) ? (true, true) : nil
        case .keyUp:
            return (false, true)
        default:
            return nil
        }
    }

    /// True if exactly the required device-independent modifiers are held.
    /// The fn flag only participates when the hotkey requires it — plenty of
    /// keys (arrows, function row) carry fn incidentally, and pre-existing
    /// hotkeys must keep matching regardless of fn state.
    private func modifiersMatch(_ required: UInt64, _ flags: CGEventFlags) -> Bool {
        var relevant: UInt64 =
            CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
            CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue
        if required & Hotkey.fnModifier != 0 { relevant |= Hotkey.fnModifier }
        return (flags.rawValue & relevant) == (required & relevant)
    }

    /// Suppress the event from reaching apps for Fn and regular-key hotkeys;
    /// leave bare modifier chords alone to avoid corrupting modifier state.
    private func shouldSuppress(_ hk: Hotkey) -> Bool {
        !hk.isModifierKey
    }
}
