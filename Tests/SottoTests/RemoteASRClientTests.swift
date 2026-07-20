import XCTest

@testable import Sotto

final class RemoteASRClientTests: XCTestCase {

    // MARK: - Response parsing

    func testParsesJSONResponse() {
        let data = Data(#"{"text":"今天天气不错。"}"#.utf8)
        XCTAssertEqual(RemoteASRClient.parseTranscriptionResponse(data), "今天天气不错。")
    }

    func testParsesVerboseJSONResponse() {
        let data = Data(#"{"task":"transcribe","language":"zh","text":" hello ","segments":[]}"#.utf8)
        XCTAssertEqual(RemoteASRClient.parseTranscriptionResponse(data), "hello")
    }

    func testRejectsNonJSONResponse() {
        XCTAssertNil(RemoteASRClient.parseTranscriptionResponse(Data("plain text".utf8)))
    }

    func testParsesOpenAIErrorEnvelope() {
        let data = Data(#"{"error":{"message":"invalid API key","type":"authentication_error"}}"#.utf8)
        XCTAssertEqual(RemoteASRClient.parseErrorMessage(data), "invalid API key")
    }

    func testParsesFlatErrorString() {
        XCTAssertEqual(
            RemoteASRClient.parseErrorMessage(Data(#"{"error":"boom"}"#.utf8)), "boom")
    }

    // MARK: - Multipart body

    func testMultipartBodyLayout() {
        let audio = Data([0x01, 0x02, 0x03])
        let body = RemoteASRClient.multipartBody(
            boundary: "B", fields: [("model", "whisper-1"), ("language", "zh")],
            fileField: "file", filename: "a.wav", fileType: "audio/wav", fileData: audio)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\nzh\r\n"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--B--\r\n"))
        XCTAssertNotNil(body.range(of: audio))
    }

    // MARK: - Test-tone WAV

    func testSampleWAVHeader() {
        let wav = RemoteASRClient.sampleWAV()
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav.subdata(in: 8..<12), as: UTF8.self), "WAVE")
        // 0.6 s at 16 kHz, 16-bit mono → 19200 PCM bytes + 44-byte header.
        XCTAssertEqual(wav.count, 44 + 19200)
    }
}
