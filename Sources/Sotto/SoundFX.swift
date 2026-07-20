import AppKit

/// Synthesized key-click feedback for the capture hotkeys, in the spirit of a
/// Mac trackpad's quiet tactile click: press = a short, dry tick; release = a
/// slightly lower tock ("got it, processing"). The committed text keeps Pop.
///
/// The ticks are tiny sine blips (fast attack, exponential decay, a soft
/// second harmonic for body) rendered once into in-memory WAVs — no bundled
/// audio assets. Keeping each cue below 60 ms makes it read as touch feedback,
/// not as a notification or success jingle.
enum SoundFX {
    private static let press = keyClick(frequency: 880, body: 225,
                                        duration: 0.046, amplitude: 0.23)
    private static let release = keyClick(frequency: 650, body: 180,
                                          duration: 0.054, amplitude: 0.21)

    static func playPress() { press?.play() }
    static func playRelease() { release?.play() }

    private static func keyClick(frequency: Double, body: Double,
                                 duration: Double, amplitude: Double) -> NSSound? {
        let sampleRate = 44100.0
        let frames = Int(sampleRate * duration)
        var samples = [Int16]()
        samples.reserveCapacity(frames)
        for i in 0..<frames {
            let seconds = Double(i) / sampleRate
            let attack = min(1.0, seconds / 0.0012)
            let tick = sin(2 * .pi * frequency * seconds) * exp(-seconds / 0.010)
            let lowBody = sin(2 * .pi * body * seconds) * exp(-seconds / 0.024)
            // A deterministic, very short transient gives the sine body a
            // physical key edge without random playback differences.
            let seed = sin(Double(i * 73 + 19) * 12.9898) * 43758.5453
            let noise = (seed - floor(seed)) * 2 - 1
            let transient = noise * exp(-seconds / 0.0035)
            let s = (tick + 0.34 * lowBody + 0.16 * transient) * amplitude * attack
            samples.append(Int16(max(-1.0, min(1.0, s)) * 32767))
        }
        return NSSound(data: wavData(samples: samples, sampleRate: Int(sampleRate)))
    }

    /// Minimal RIFF/WAVE wrapper: mono, 16-bit PCM.
    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var d = Data()
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func append(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                      // fmt chunk size
        append(UInt16(1))                       // PCM
        append(UInt16(1))                       // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))          // byte rate
        append(UInt16(2))                       // block align
        append(UInt16(16))                      // bits per sample
        d.append(contentsOf: Array("data".utf8))
        append(dataSize)
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
