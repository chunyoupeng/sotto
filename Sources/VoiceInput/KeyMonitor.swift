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

    var holdHotkey: Hotkey? = .fn
    var holdEnabled = true
    var toggleHotkey: Hotkey? = nil
    var toggleEnabled = false
    var dashboardHotkey: Hotkey? = nil

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Pressed state to debounce repeated flagsChanged / key autorepeat.
    private var holdActive = false
    private var toggleActive = false
    private var dashboardActive = false

    /// Reconfigure from current `AppSettings`.
    func reload() {
        holdHotkey = AppSettings.holdEnabled ? AppSettings.holdHotkey : nil
        holdEnabled = AppSettings.holdEnabled
        toggleHotkey = AppSettings.toggleEnabled ? AppSettings.toggleHotkey : nil
        toggleEnabled = AppSettings.toggleEnabled
        dashboardHotkey = AppSettings.dashboardEnabled ? AppSettings.dashboardHotkey : nil
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
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // --- Hold key ---
        if let hk = holdHotkey {
            if let (down, matched) = match(hk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !holdActive {
                        holdActive = true
                        DispatchQueue.main.async { [weak self] in self?.onHoldDown?() }
                        if shouldSuppress(hk) { return nil }
                    } else if !down && holdActive {
                        holdActive = false
                        DispatchQueue.main.async { [weak self] in self?.onHoldUp?() }
                        if shouldSuppress(hk) { return nil }
                    } else if shouldSuppress(hk) && !hk.isModifierKey {
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
                    if down && !toggleActive {
                        toggleActive = true
                        DispatchQueue.main.async { [weak self] in self?.onToggleDown?() }
                        if shouldSuppress(tk) { return nil }
                    } else if !down {
                        toggleActive = false
                        if shouldSuppress(tk) { return nil }
                    } else if shouldSuppress(tk) && !tk.isModifierKey {
                        return nil
                    }
                }
            }
        }

        // --- Dashboard key ---
        if let dk = dashboardHotkey {
            if let (down, matched) = match(dk, type: type, keyCode: keyCode, flags: flags) {
                if matched {
                    if down && !dashboardActive {
                        dashboardActive = true
                        DispatchQueue.main.async { [weak self] in self?.onDashboardDown?() }
                        if shouldSuppress(dk) { return nil }
                    } else if !down {
                        dashboardActive = false
                        if shouldSuppress(dk) { return nil }
                    } else if shouldSuppress(dk) && !dk.isModifierKey {
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
            // Bare modifier key: a flagsChanged whose keycode is this modifier.
            guard type == .flagsChanged, keyCode == hk.keyCode else { return nil }
            return (flags.contains(modFlag), true)
        }
        // Regular key.
        guard keyCode == hk.keyCode else { return nil }
        if type == .keyDown {
            return (modifiersMatch(hk.modifiers, flags), true)
        } else if type == .keyUp {
            return (false, true)
        }
        return nil
    }

    /// True if exactly the required device-independent modifiers are held.
    private func modifiersMatch(_ required: UInt64, _ flags: CGEventFlags) -> Bool {
        let relevant: UInt64 =
            CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
            CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue
        return (flags.rawValue & relevant) == (required & relevant)
    }

    /// Suppress the event from reaching apps for Fn and regular-key hotkeys;
    /// leave bare modifier chords alone to avoid corrupting modifier state.
    private func shouldSuppress(_ hk: Hotkey) -> Bool {
        !hk.isModifierKey
    }
}
