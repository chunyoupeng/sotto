import CoreAudio
import Foundation

/// Temporarily silences the system output device while the mic is recording,
/// so background music or video never bleeds into the dictation. Prefers the
/// device's hardware mute switch; devices without one fall back to dropping
/// the main volume to zero. Whatever was changed is restored exactly (a user
/// who was already muted stays muted afterwards).
final class SystemMuteGuard {
    /// Pending restore action for the device we changed; nil when inactive.
    private var restore: (() -> Void)?

    func mute() {
        guard restore == nil, let device = Self.defaultOutputDevice() else { return }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if Self.isSettable(device, &muteAddr) {
            guard let current: UInt32 = Self.read(device, &muteAddr) else { return }
            guard current == 0 else { return }  // already muted by the user
            Self.write(device, &muteAddr, UInt32(1))
            restore = { var a = muteAddr; Self.write(device, &a, UInt32(0)) }
            return
        }

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if Self.isSettable(device, &volAddr),
           let volume: Float32 = Self.read(device, &volAddr), volume > 0 {
            Self.write(device, &volAddr, Float32(0))
            restore = { var a = volAddr; Self.write(device, &a, volume) }
        }
    }

    func unmute() {
        restore?()
        restore = nil
    }

    // MARK: - CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isSettable(_ device: AudioDeviceID,
                                   _ addr: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr
            && settable.boolValue
    }

    private static func read<T>(_ device: AudioDeviceID,
                                _ addr: inout AudioObjectPropertyAddress) -> T? {
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.pointee
    }

    private static func write(_ device: AudioDeviceID,
                              _ addr: inout AudioObjectPropertyAddress, _ value: UInt32) {
        var v = value
        let status = AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        if status != noErr {
            SottoLog.log("MuteGuard", "failed to set output property: \(status)")
        }
    }

    private static func write(_ device: AudioDeviceID,
                              _ addr: inout AudioObjectPropertyAddress, _ value: Float32) {
        var v = value
        let status = AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if status != noErr {
            SottoLog.log("MuteGuard", "failed to set output property: \(status)")
        }
    }
}
