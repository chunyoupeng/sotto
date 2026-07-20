import AVFoundation
import Foundation

private func logToFile(_ message: String) {
    SottoLog.log("SpeechEngine", message)
}

/// Speech recognition. Audio is recorded natively and written to a temporary
/// 16 kHz mono WAV, then transcribed by the configured backend:
///
/// - `local`: an MLX ASR model (Qwen3-ASR) in a Python sidecar. It is launched
///   lazily by the first local transcription and released when online ASR is
///   selected.
/// - `openai`: a remote OpenAI Whisper-compatible `/audio/transcriptions`
///   endpoint (see `RemoteASRClient`). No local model or Python needed.
///
/// The backend is re-read per utterance, so switching in Settings takes effect
/// immediately; the local daemon is only launched once a local transcription
/// is actually needed.
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
    /// Loudest normalized level seen this recording (written on the audio tap
    /// thread, read once after the tap is removed). Silence never reaching
    /// `speechLevelThreshold` skips ASR entirely: with hotword biasing active,
    /// a silent clip reliably hallucinates dictionary words ("Python" from
    /// nothing), so an empty utterance must never leave the machine.
    private var peakLevel: Float = 0
    private static let speechLevelThreshold: Float = 0.15

    /// Selected locale; only the language part is forwarded to the model.
    var locale: Locale
    /// When enabled, omit the language hint so Qwen3-ASR can detect it from
    /// each utterance (including mixed-language speech).
    var automaticallyDetectsLanguage = false

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var currentRecordingURL: URL?

    // MARK: - Daemon

    private var process: Process?
    private var stdinHandle: FileHandle?
    private let daemonQueue = DispatchQueue(label: "com.chunyoupeng.Sotto.asr")
    private var isReady = false
    private var nextID = 0
    private var pending: [Int: (Result<String, Error>) -> Void] = [:]
    private var queuedLines: [Data] = []
    private var stdoutBuffer = Data()
    /// Consecutive failed launches. Reset on "ready"; relaunches back off
    /// exponentially and give up (with a user-visible error) after `maxRelaunches`.
    private var relaunchAttempts = 0
    private let maxRelaunches = 5
    /// Set once relaunching is abandoned; new requests then fail immediately
    /// instead of queuing for a daemon that will never come up.
    private var gaveUp = false
    /// Whether `launchDaemon` has been requested (guarded by `daemonQueue`).
    private var daemonStarted = false
    /// False after online ASR is selected, preventing crash-retry timers from
    /// resurrecting a local model the user no longer wants in memory.
    private var wantsDaemon = false

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
    }

    /// Apply a settings/menu backend change immediately. Local ASR remains
    /// lazy; online ASR tears down any previously loaded sidecar.
    func applyBackendSelection() {
        daemonQueue.async { [weak self] in
            guard let self else { return }
            if AppSettings.asrBackend == .openAI {
                self.stopDaemon()
            }
        }
    }

    /// Must run on `daemonQueue`.
    private func startDaemonIfNeeded() {
        wantsDaemon = true
        guard !daemonStarted else { return }
        daemonStarted = true
        gaveUp = false
        relaunchAttempts = 0
        launchDaemon()
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

        // No usable input device (or mic permission missing) reports a 0 Hz
        // format; installing a tap with it raises an ObjC exception and crashes.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            onError?("没有可用的麦克风输入")
            return
        }

        // Target: 16 kHz mono — what the ASR model expects.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sotto-\(UUID().uuidString).wav")
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
        peakLevel = 0

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
        // Meter before any gain so the level (UI + silence gate) reflects the
        // real input, not whisper-mode's amplified signal.
        meter(buffer)
        if AppSettings.whisperModeEnabled {
            applyWhisperGain(to: buffer)
        }
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

    }

    /// RMS → normalized 0..1 level, feeding the UI and the silence gate.
    private func meter(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrtf(sum / Float(max(frameLength, 1)))
        let dB = 20 * log10(max(rms, 1e-6))
        let normalized = max(Float(0), min(Float(1), (dB + 50) / 40))
        peakLevel = max(peakLevel, normalized)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(normalized)
        }
    }

    /// Quiet-speech mode raises the signal before ASR conversion. A soft clip
    /// keeps sudden normal-volume syllables from wrapping/distorting like a hard
    /// integer gain would. This is intentionally local and deterministic.
    private func applyWhisperGain(to buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let gain: Float = 2.4
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                let amplified = samples[frame] * gain
                samples[frame] = amplified / (1 + abs(amplified))
            }
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        guard let url = currentRecordingURL else { return nil }
        audioFile = nil  // flush & close the file
        converter = nil
        currentRecordingURL = nil

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        // Silence gate: nothing loud enough to be speech was heard, so don't
        // transcribe at all — report an empty utterance (the caller shows its
        // "nothing heard" notice and cleans up the WAV).
        if peakLevel < Self.speechLevelThreshold {
            logToFile("silence gate: peak \(peakLevel) < \(Self.speechLevelThreshold), skipping ASR")
            DispatchQueue.main.async { [weak self] in
                self?.onFinalResultFull?("", url, duration)
                self?.onFinalResult?("")
            }
            return url
        }

        let language = automaticallyDetectsLanguage
            ? nil
            : locale.language.languageCode?.identifier
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
        return url
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
        let dev = AppSettings.devRepoRoot.appendingPathComponent("Resources/asr_server.py").path
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    /// Must run on `daemonQueue`.
    private func launchDaemon() {
        guard wantsDaemon else { return }
        // Launch failures retry with the same backoff as crashes: the engine or
        // Python may live on a volume that isn't mounted yet at login. Queued
        // requests are kept — their WAVs still exist — so they replay on success.
        guard let (exe, args) = engineCommand() else {
            logToFile("ASR engine not found (no frozen engine, no script)")
            scheduleRelaunch()
            return
        }

        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["SOTTO_ASR_MODEL"] = modelPath()
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
            scheduleRelaunch()
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
        daemonStarted = false
        // Fail everything in flight; also drop queued requests — their pending
        // callbacks are being failed here, so replaying the lines after a
        // relaunch would transcribe into the void (and the WAVs may be gone).
        failAllRequests(.daemonUnavailable)
        if wantsDaemon { scheduleRelaunch() }
    }

    /// Must run on `daemonQueue`. Explicit online selection is authoritative:
    /// cancel pending local work, detach handlers, and release model memory.
    private func stopDaemon() {
        wantsDaemon = false
        daemonStarted = false
        isReady = false
        gaveUp = false
        relaunchAttempts = 0
        stdoutBuffer.removeAll()
        failAllRequests(.daemonUnavailable)
        stdinHandle = nil
        guard let proc = process else { return }
        process = nil
        proc.terminationHandler = nil
        if proc.isRunning { proc.terminate() }
        logToFile("local daemon stopped (online backend selected)")
    }

    /// Must run on `daemonQueue`. Shared backoff for a daemon that crashed and
    /// one that never launched.
    private func scheduleRelaunch() {
        guard wantsDaemon else { return }
        relaunchAttempts += 1
        guard relaunchAttempts <= maxRelaunches else {
            gaveUp = true
            logToFile("daemon failed \(maxRelaunches) times in a row, giving up")
            failAllRequests(.daemonUnavailable)
            DispatchQueue.main.async { [weak self] in
                self?.onError?("语音引擎多次启动失败，已停止重试。请检查模型和 Python 路径后重启 Sotto。")
            }
            return
        }
        let delay = min(0.5 * pow(2.0, Double(relaunchAttempts - 1)), 8.0)
        logToFile("relaunching daemon in \(delay)s (attempt \(relaunchAttempts)/\(maxRelaunches))")
        daemonQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.wantsDaemon, self.process == nil else { return }
            self.daemonStarted = true
            self.launchDaemon()
        }
    }

    /// Must run on `daemonQueue`.
    private func failAllRequests(_ error: EngineError) {
        queuedLines.removeAll()
        let failing = pending
        pending.removeAll()
        for (_, cb) in failing {
            cb(.failure(error))
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
                relaunchAttempts = 0
                gaveUp = false
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
        if AppSettings.asrBackend == .openAI {
            RemoteASRClient.transcribe(
                audioURL: audioURL, language: language,
                prompt: PromptComposer.asrContext(SottoConfig.readHotwords()),
                baseURL: AppSettings.asrAPIBaseURL,
                apiKey: AppSettings.asrAPIKey,
                model: AppSettings.asrAPIModel,
                completion: completion)
            return
        }
        daemonQueue.async { [weak self] in
            guard let self else { return }
            self.startDaemonIfNeeded()
            guard !self.gaveUp else {
                completion(.failure(EngineError.daemonUnavailable))
                return
            }
            let id = self.nextID
            self.nextID += 1
            self.pending[id] = completion

            var req: [String: Any] = ["id": id, "audio": audioURL.path]
            if let language { req["language"] = language }
            // Bias recognition toward the user's hotwords at decode time (the
            // ASR "first layer"), passed as Qwen3-ASR's system prompt.
            if let context = PromptComposer.asrContext(SottoConfig.readHotwords()) {
                req["system_prompt"] = context
            }
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
