import Foundation

/// Client for an OpenAI Whisper-compatible transcription endpoint
/// (`POST {base}/audio/transcriptions`, multipart form). Lets Sotto use any
/// hosted ASR service — official OpenAI, or a self-hosted server such as
/// vLLM / faster-whisper / qwen-asr behind an OpenAI-compatible gateway.
enum RemoteASRClient {

    /// Transcribe a WAV file. `language` is an ISO-639-1 code ("zh", "en") or
    /// nil for auto-detect; `prompt` biases recognition toward hotwords (the
    /// Whisper API's `prompt` field plays the same role as the local engine's
    /// system prompt).
    static func transcribe(
        audioURL: URL, language: String?, prompt: String?,
        baseURL: String, apiKey: String, model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            completion(.failure(ClientError.audioUnreadable(error.localizedDescription)))
            return
        }
        transcribe(audioData: audioData, filename: audioURL.lastPathComponent,
                   language: language, prompt: prompt,
                   baseURL: baseURL, apiKey: apiKey, model: model,
                   completion: completion)
    }

    static func transcribe(
        audioData: Data, filename: String, language: String?, prompt: String?,
        baseURL: String, apiKey: String, model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard !trimmed.isEmpty, let url = URL(string: "\(trimmed)/audio/transcriptions") else {
            completion(.failure(ClientError.invalidURL))
            return
        }

        var fields: [(String, String)] = [("model", model)]
        if let language, !language.isEmpty { fields.append(("language", language)) }
        if let prompt, !prompt.isEmpty { fields.append(("prompt", prompt)) }

        let boundary = "sotto-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Uploads carry the whole utterance, and a self-hosted server may be
        // cold; give it more headroom than a chat request.
        request.timeoutInterval = 60
        request.httpBody = multipartBody(
            boundary: boundary, fields: fields,
            fileField: "file", filename: filename,
            fileType: "audio/wav", fileData: audioData)

        SottoLog.log("RemoteASR", "request model=\(model) bytes=\(audioData.count) lang=\(language ?? "auto")")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                SottoLog.log("RemoteASR", "network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(ClientError.invalidResponse))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let message = parseErrorMessage(data) ?? "HTTP \(status)"
                SottoLog.log("RemoteASR", "server error (\(status)): \(message)")
                completion(.failure(ClientError.server(message)))
                return
            }
            guard let text = parseTranscriptionResponse(data) else {
                SottoLog.log("RemoteASR", "unparseable response")
                completion(.failure(ClientError.invalidResponse))
                return
            }
            SottoLog.content("RemoteASR", "text: \(text)")
            completion(.success(text))
        }
        task.resume()
    }

    /// Extract `text` from an OpenAI-style transcription response (`json` or
    /// `verbose_json` shapes both carry a top-level "text").
    static func parseTranscriptionResponse(_ data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// OpenAI error envelope: {"error": {"message": ...}}.
    static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        return json["error"] as? String ?? json["message"] as? String
    }

    static func multipartBody(
        boundary: String, fields: [(String, String)],
        fileField: String, filename: String, fileType: String, fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(fileType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    // MARK: - Connection test

    /// Settings "测试" support: send a short generated WAV so success proves the
    /// URL, key, and model name are all accepted — without recording anything.
    static func test(baseURL: String, apiKey: String, model: String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        transcribe(audioData: sampleWAV(), filename: "sotto-test.wav",
                   language: nil, prompt: nil,
                   baseURL: baseURL, apiKey: apiKey, model: model) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 0.6 s of a soft 440 Hz tone as 16 kHz mono 16-bit PCM WAV. A pure tone
    /// (not silence) so servers that reject empty audio still accept it.
    static func sampleWAV() -> Data {
        let sampleRate = 16_000
        let frames = sampleRate * 6 / 10
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let t = Double(i) / Double(sampleRate)
            let sample = Int16(sin(2 * .pi * 440 * t) * 3000)
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func append(_ s: String) { wav.append(Data(s.utf8)) }
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + pcm.count)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
        append16(2); append16(16)
        append("data"); append32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case audioUnreadable(String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "在线识别接口地址无效"
            case .invalidResponse: return "在线识别接口返回了无法解析的内容"
            case .audioUnreadable(let msg): return "无法读取录音文件：\(msg)"
            case .server(let msg): return "在线识别失败：\(msg)"
            }
        }
    }
}
