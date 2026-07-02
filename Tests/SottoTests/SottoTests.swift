import XCTest
@testable import Sotto

final class HotkeyTests: XCTestCase {
    func testFnHotkey() {
        XCTAssertTrue(Hotkey.fn.isFn)
        XCTAssertFalse(Hotkey.fn.isModifierKey)
        XCTAssertEqual(Hotkey.fn.displayString, "fn")
    }

    func testModifierKeyDetection() {
        let rightCmd = Hotkey(keyCode: 54, modifiers: 0)
        XCTAssertTrue(rightCmd.isModifierKey)
        XCTAssertEqual(Hotkey.modifierFlag(forKeyCode: 54), .maskCommand)
        XCTAssertEqual(rightCmd.displayString, "Right ⌘")
        XCTAssertNil(Hotkey.modifierFlag(forKeyCode: 2))  // D is not a modifier
    }

    func testComboDisplayString() {
        let ctrlCmdD = Hotkey(
            keyCode: 2,
            modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue)
        XCTAssertEqual(ctrlCmdD.displayString, "⌃⌘D")
    }

    func testCodableRoundtrip() throws {
        let original = Hotkey(keyCode: 49, modifiers: CGEventFlags.maskAlternate.rawValue)
        let decoded = Hotkey.decode(original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertNil(Hotkey.decode(nil))
        XCTAssertNil(Hotkey.decode(Data()))
    }
}

final class ChatResponseParsingTests: XCTestCase {
    func testParsesValidResponse() {
        let json = """
            {"choices": [{"message": {"role": "assistant", "content": "你好，世界"}}]}
            """.data(using: .utf8)!
        XCTAssertEqual(LLMRefiner.parseChatResponse(json), "你好，世界")
    }

    func testRejectsMalformedResponses() {
        for bad in [
            "not json",
            "{}",
            #"{"choices": []}"#,
            #"{"choices": [{"message": {}}]}"#,
            #"{"choices": [{"message": {"content": 42}}]}"#,
        ] {
            XCTAssertNil(LLMRefiner.parseChatResponse(bad.data(using: .utf8)!), bad)
        }
    }

    func testDefaultPromptIsNeverEmpty() {
        XCTAssertFalse(LLMRefiner.defaultSystemPrompt.isEmpty)
    }
}

final class DictationRecordTests: XCTestCase {
    private func record(raw: String, refined: String, corrected: String? = nil,
                        duration: Double = 6.0) -> DictationRecord {
        DictationRecord(id: "t", date: Date(), durationSeconds: duration,
                        rawText: raw, refinedText: refined, audioFileName: nil,
                        correctedText: corrected)
    }

    func testDisplayTextPrefersCorrection() {
        XCTAssertEqual(record(raw: "a", refined: "b").displayText, "b")
        XCTAssertEqual(record(raw: "a", refined: "b", corrected: "c").displayText, "c")
        XCTAssertEqual(record(raw: "a", refined: "b", corrected: "").displayText, "b")
    }

    func testCharCountIgnoresWhitespace() {
        XCTAssertEqual(record(raw: "", refined: "你好 world\n").charCount, 7)
    }

    func testCharsPerMinute() {
        let r = record(raw: "", refined: "十个字十个字十个字十", duration: 30)
        XCTAssertEqual(r.charsPerMinute, 20, accuracy: 0.001)
        XCTAssertEqual(record(raw: "", refined: "x", duration: 0).charsPerMinute, 0)
    }
}

final class RecordStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SottoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Poll until `condition` holds, so async persistence can be awaited without
    /// fixed sleeps.
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(20_000)
        }
        return condition()
    }

    func testAddAndRecentOrdering() {
        let store = RecordStore(baseDir: dir)
        store.add(rawText: "第一条", refinedText: "第一条", duration: 1, tempAudioURL: nil)
        store.add(rawText: "第二条", refinedText: "第二条", duration: 2, tempAudioURL: nil)
        XCTAssertEqual(store.totalCount, 2)
        XCTAssertEqual(store.recent().first?.rawText, "第二条")
    }

    func testPersistenceRoundtrip() {
        let store = RecordStore(baseDir: dir)
        store.add(rawText: "raw", refinedText: "refined", duration: 3, tempAudioURL: nil)
        let json = dir.appendingPathComponent("history.json")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: json.path) })

        let reloaded = RecordStore(baseDir: dir)
        XCTAssertEqual(reloaded.totalCount, 1)
        XCTAssertEqual(reloaded.recent().first?.refinedText, "refined")
    }

    func testCorruptHistoryIsBackedUpNotLost() throws {
        let json = dir.appendingPathComponent("history.json")
        try "this is not json".write(to: json, atomically: true, encoding: .utf8)

        let store = RecordStore(baseDir: dir)
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("history.corrupt.json").path))
    }

    func testSetCorrectionAndTrainingExport() throws {
        let store = RecordStore(baseDir: dir)
        store.add(rawText: "派森", refinedText: "派森", duration: 1, tempAudioURL: nil)
        let id = store.recent().first!.id

        store.setCorrection(id: id, correctedText: "Python")
        XCTAssertEqual(store.correctedCount, 1)
        XCTAssertEqual(store.recent().first?.displayText, "Python")

        let out = dir.appendingPathComponent("train.jsonl")
        XCTAssertEqual(try store.exportTrainingData(to: out), 1)
        let line = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(line.contains("\"raw\""))
        XCTAssertTrue(line.contains("Python"))

        // Whitespace-only correction clears it.
        store.setCorrection(id: id, correctedText: "   ")
        XCTAssertEqual(store.correctedCount, 0)
    }
}
