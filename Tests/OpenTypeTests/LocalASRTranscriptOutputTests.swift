import XCTest
@testable import OpenType

final class LocalASRTranscriptOutputTests: XCTestCase {
    func testParsesPlainAndTopLevelJSONRunnerOutput() throws {
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"text":" 你好，OpenType。 "}"#),
            "你好，OpenType。"
        )
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput("Good morning."),
            "Good morning."
        )
    }

    func testParsesRunnerJSONAfterStdoutLogs() throws {
        let output = """
        Loading local ASR model...
        {"text":"今天下午同步发布计划。","language":"zh"}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "今天下午同步发布计划。"
        )
    }

    func testParsesNestedRunnerTranscriptFields() throws {
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"result":{"transcript":"Ship tomorrow."}}"#),
            "Ship tomorrow."
        )
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"data":{"transcription":"金曜の午後に会議します。"}}"#),
            "金曜の午後に会議します。"
        )
    }

    func testParsesSegmentedRunnerOutput() throws {
        let output = """
        {"segments":[{"text":"Ship the release notes."},{"text":"Then confirm QA."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testParsesChunkedRunnerOutput() throws {
        let output = """
        {"chunks":[{"timestamp":[0.0,1.2],"text":"Ship the release notes."},{"timestamp":[1.2,2.4],"text":"Then confirm QA."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testParsesTopLevelSegmentArrayRunnerOutput() throws {
        let output = """
        [{"text":"Ship the release notes."},{"text":"Then confirm QA."}]
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testParsesFirstAlternativeFromRunnerResults() throws {
        let output = """
        {"results":[{"alternatives":[{"transcript":"Ship the release notes."},{"transcript":"Skip the release notes."}]},{"alternatives":[{"transcript":"Then confirm QA."},{"transcript":"Then confirm queue A."}]}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testParsesFirstHypothesisFromRunnerOutput() throws {
        let output = """
        {"nBest":[{"text":"Ship the release notes today."},{"text":"Skip the release notes today."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testTreatsNoSpeechPlaceholderAsEmpty() throws {
        XCTAssertEqual(try LocalASREngine.parseRunnerOutput(#"{"text":"（无）"}"#), "")
        XCTAssertEqual(try LocalASREngine.parseRunnerOutput(#"{"text":" ( 无 ) "}"#), "")
    }
}
