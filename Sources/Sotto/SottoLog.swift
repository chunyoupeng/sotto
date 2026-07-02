import Foundation

/// Shared file logger for `~/Library/Logs/Sotto.log`.
///
/// Two levels of logging:
/// - `log` — operational events (daemon lifecycle, errors). Always written.
/// - `content` — anything containing what the user actually said (transcripts,
///   LLM responses). Only written when `debugLogging` is enabled in
///   `~/.sotto/config.json`, so dictated text is never persisted by default.
///
/// Writes happen on a serial background queue (never blocks the caller) and the
/// file is rotated once it exceeds `maxBytes` (one `.old` generation is kept).
enum SottoLog {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Sotto.log")

    private static let queue = DispatchQueue(label: "com.chunyoupeng.Sotto.log", qos: .utility)
    private static let maxBytes: UInt64 = 2 * 1024 * 1024

    /// Opt-in switch for logging dictated content; read once per launch.
    static let contentLoggingEnabled: Bool = SottoConfig.bool("debugLogging") ?? false

    static func log(_ category: String, _ message: String) {
        write("[\(category)] \(message)")
    }

    /// Log a message that contains user-dictated text. Dropped unless the user
    /// has explicitly enabled `debugLogging`.
    static func content(_ category: String, _ message: String) {
        guard contentLoggingEnabled else { return }
        write("[\(category)] \(message)")
    }

    private static func write(_ line: String) {
        let msg = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        queue.async {
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = msg.data(using: .utf8) { handle.write(data) }
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: fileURL.path, contents: msg.data(using: .utf8))
            }
        }
    }

    /// Must run on `queue`.
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64, size > maxBytes else { return }
        let old = fileURL.deletingPathExtension().appendingPathExtension("log.old")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: fileURL, to: old)
    }
}
