import AVFoundation
import Foundation

private let logger_subsystem = "com.yetone.VoiceInput"

private func logToFile(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] [SpeechEngine] \(message)\n"
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VoiceInput.log")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(msg.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logURL.path, contents: msg.data(using: .utf8))
    }
}

/// Speech recognition backed by a local MLX ASR model (Qwen3-ASR) running in a
/// resident Python sidecar process. Audio is recorded natively, written to a
/// temporary 16 kHz mono WAV, and handed to the daemon for transcription.
///
/// The daemon stays loaded in memory for the lifetime of the app so each
/// utterance only pays inference cost (~0.5 s), not model load (~1 s).
final class SpeechEngine {
    var onPartialResult: ((String) -> Void)?   // kept for API compatibility (no streaming in v1)
    var onFinalResult: ((String) -> Void)?
    /// Richer final callback: raw ASR text, the recorded WAV (caller owns cleanup),
    /// and the spoken duration in seconds.
    var onFinalResultFull: ((String, URL?, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onLocaleUnavailable: ((String) -> Void)?  // kept for API compatibility (unused)

    private var recordingStartTime: Date?

    /// Selected locale; only the language part is forwarded to the model.
    var locale: Locale

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var currentRecordingURL: URL?

    // MARK: - Daemon

    private var process: Process?
    private var stdinHandle: FileHandle?
    private let daemonQueue = DispatchQueue(label: "com.yetone.VoiceInput.asr")
    private var isReady = false
    private var nextID = 0
    private var pending: [Int: (Result<String, Error>) -> Void] = [:]
    private var queuedLines: [Data] = []
    private var stdoutBuffer = Data()
    private var didTryRelaunch = false

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        daemonQueue.async { [weak self] in self?.launchDaemon() }
    }

    // MARK: - Permissions

    static func requestPermissions(completion: @escaping (Bool, String?) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if granted {
                    completion(true, nil)
                } else {
                    completion(
                        false,
                        "Microphone access denied.\nGrant in System Settings → Privacy & Security → Microphone."
                    )
                }
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: 16 kHz mono — what the ASR model expects.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceinput-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            onError?("Failed to create audio file: \(error.localizedDescription)")
            return
        }
        guard let conv = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
            onError?("Failed to create audio converter")
            return
        }

        audioFile = file
        converter = conv
        currentRecordingURL = url

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            recordingStartTime = Date()
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            cleanupRecording(deleteFile: true)
        }
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile, let converter else { return }
        let outFormat = file.processingFormat

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 256
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var convError: NSError?
        converter.convert(to: outBuffer, error: &convError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let convError {
            logToFile("convert error: \(convError.localizedDescription)")
        }
        if outBuffer.frameLength > 0 {
            try? file.write(from: outBuffer)
        }

        // Audio level metering from the original buffer.
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrtf(sum / Float(max(frameLength, 1)))
        let dB = 20 * log10(max(rms, 1e-6))
        let normalized = max(Float(0), min(Float(1), (dB + 50) / 40))
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(normalized)
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        guard let url = currentRecordingURL else { return }
        audioFile = nil  // flush & close the file
        converter = nil
        currentRecordingURL = nil

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        let language = locale.language.languageCode?.identifier
        transcribe(audioURL: url, language: language) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    // The caller owns the WAV from here (saves or deletes it).
                    self.onFinalResultFull?(text, url, duration)
                    self.onFinalResult?(text)
                case .failure(let error):
                    try? FileManager.default.removeItem(at: url)
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recordingStartTime = nil
        cleanupRecording(deleteFile: true)
    }

    private func cleanupRecording(deleteFile: Bool) {
        audioFile = nil
        converter = nil
        if deleteFile, let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
    }

    // MARK: - Daemon lifecycle

    private func pythonPath() -> String {
        let override = AppSettings.asrPythonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty, FileManager.default.fileExists(atPath: override) {
            return override
        }
        return AppSettings.devPythonPath
    }

    private func modelPath() -> String {
        let fm = FileManager.default
        // 1. Explicit user override.
        let override = AppSettings.asrModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty, fm.fileExists(atPath: override) { return override }
        // 2. Managed model dir under ~/.sotto.
        let managed = AppSettings.defaultManagedModelURL.path
        if fm.fileExists(atPath: managed) { return managed }
        // 3. Model bundled inside the app (legacy/self-contained builds).
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("models/\(AppSettings.defaultModelName)").path
            if fm.fileExists(atPath: bundled) { return bundled }
        }
        // 4. Dev cache fallback (this machine).
        return AppSettings.devModelPath
    }

    /// The ASR engine command. Prefers the self-contained frozen engine bundled
    /// in the app (no Python/venv needed); falls back to the Python script.
    private func engineCommand() -> (URL, [String])? {
        if let res = Bundle.main.resourceURL {
            let frozen = res.appendingPathComponent("asr_engine/asr_engine")
            if FileManager.default.isExecutableFile(atPath: frozen.path) {
                return (frozen, [])
            }
        }
        guard let script = scriptPath() else { return nil }
        return (URL(fileURLWithPath: pythonPath()), [script])
    }

    private func scriptPath() -> String? {
        if let url = Bundle.main.url(forResource: "asr_server", withExtension: "py") {
            return url.path
        }
        let dev = "/Users/pengchunyou/Projects/voice-input-dist/Resources/asr_server.py"
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    /// Must run on `daemonQueue`.
    private func launchDaemon() {
        guard let (exe, args) = engineCommand() else {
            logToFile("ASR engine not found (no frozen engine, no script)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("ASR engine not found in app bundle")
            }
            return
        }

        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["VOICEINPUT_ASR_MODEL"] = modelPath()
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.daemonQueue.async { self?.handleStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                logToFile("daemon: \(s.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        proc.terminationHandler = { [weak self] p in
            logToFile("daemon exited, status \(p.terminationStatus)")
            self?.daemonQueue.async { self?.handleDaemonExit() }
        }

        do {
            try proc.run()
        } catch {
            logToFile("failed to launch daemon: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Failed to start ASR engine: \(error.localizedDescription)")
            }
            return
        }

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        logToFile("daemon launched (model=\(modelPath()))")
    }

    /// Must run on `daemonQueue`.
    private func handleDaemonExit() {
        isReady = false
        stdinHandle = nil
        process = nil
        let failing = pending
        pending.removeAll()
        for (_, cb) in failing {
            cb(.failure(EngineError.daemonUnavailable))
        }
        if !didTryRelaunch {
            didTryRelaunch = true
            logToFile("relaunching daemon")
            launchDaemon()
        }
    }

    /// Must run on `daemonQueue`.
    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0a) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            switch type {
            case "ready":
                isReady = true
                didTryRelaunch = false
                logToFile("daemon ready")
                let queued = queuedLines
                queuedLines.removeAll()
                for line in queued { writeLine(line) }
            case "result":
                if let id = obj["id"] as? Int, let cb = pending.removeValue(forKey: id) {
                    cb(.success((obj["text"] as? String ?? "")))
                }
            case "error":
                if let id = obj["id"] as? Int, let cb = pending.removeValue(forKey: id) {
                    cb(.failure(EngineError.transcription(obj["error"] as? String ?? "unknown")))
                }
            case "fatal":
                logToFile("daemon fatal: \(obj["error"] as? String ?? "")")
                let failing = pending
                pending.removeAll()
                for (_, cb) in failing {
                    cb(.failure(EngineError.transcription(obj["error"] as? String ?? "model failed to load")))
                }
            default:
                break
            }
        }
    }

    private func transcribe(
        audioURL: URL, language: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        daemonQueue.async { [weak self] in
            guard let self else { return }
            let id = self.nextID
            self.nextID += 1
            self.pending[id] = completion

            var req: [String: Any] = ["id": id, "audio": audioURL.path]
            if let language { req["language"] = language }
            guard var line = try? JSONSerialization.data(withJSONObject: req) else {
                self.pending.removeValue(forKey: id)
                completion(.failure(EngineError.transcription("failed to encode request")))
                return
            }
            line.append(0x0a)

            if self.isReady {
                self.writeLine(line)
            } else {
                self.queuedLines.append(line)
            }
        }
    }

    /// Must run on `daemonQueue`.
    private func writeLine(_ line: Data) {
        guard let handle = stdinHandle else { return }
        do {
            try handle.write(contentsOf: line)
        } catch {
            logToFile("stdin write failed: \(error.localizedDescription)")
        }
    }

    enum EngineError: LocalizedError {
        case daemonUnavailable
        case transcription(String)

        var errorDescription: String? {
            switch self {
            case .daemonUnavailable: return "ASR engine unavailable"
            case .transcription(let msg): return "Transcription failed: \(msg)"
            }
        }
    }
}
