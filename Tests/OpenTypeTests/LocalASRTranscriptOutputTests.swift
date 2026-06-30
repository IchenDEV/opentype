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

    func testParsesWordLevelRunnerOutput() throws {
        let output = """
        {"words":[{"word":"Ship"},{"word":"the"},{"word":"release"},{"word":"notes"},{"word":"today"},{"word":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesCJKWordLevelRunnerOutputWithoutExtraSpaces() throws {
        let output = """
        {"words":[{"word":"今天"},{"word":"下午"},{"word":"发布"},{"word":"。"}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "今天下午发布。"
        )
    }

    func testParsesAWSItemAlternativesFromRunnerOutput() throws {
        let output = """
        {"results":{"items":[{"alternatives":[{"content":"Ship","confidence":"0.99"}]},{"alternatives":[{"content":"the"}]},{"alternatives":[{"content":"release"}]},{"alternatives":[{"content":"notes"}]},{"alternatives":[{"content":"today"}]},{"alternatives":[{"content":"."}],"type":"punctuation"}]}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
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

    func testSelectsHighestConfidenceAlternativeFromRunnerResults() throws {
        let output = """
        {"alternatives":[{"transcript":"Skip the release notes today.","confidence":0.42},{"transcript":"Ship the release notes today.","confidence":0.91}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testKeepsFirstAlternativeWithoutConfidenceScores() throws {
        let output = """
        {"alternatives":[{"transcript":"Ship the release notes today."},{"transcript":"Skip the release notes today."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesNestedAndPercentConfidenceScores() throws {
        let output = """
        {"hypotheses":[{"transcript":"Skip the release notes today.","confidence":{"score":"62%"}},{"transcript":"Ship the release notes today.","confidence":{"score":"93%"}}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
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

    func testParsesRecognizedPhrasesFromRunnerOutput() throws {
        let output = """
        {"recognizedPhrases":[{"nBest":[{"display":"Skip the release notes today.","confidence":0.41},{"display":"Ship the release notes today.","confidence":0.93}]}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesChannelAlternativesFromRunnerOutput() throws {
        let output = """
        {"results":{"channels":[{"alternatives":[{"transcript":"Ship the release notes today."},{"transcript":"Skip the release notes today."}]}]}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesTranscriptsContainerFromRunnerOutput() throws {
        let output = """
        {"results":{"transcripts":[{"transcript":"Ship the release notes today."}]}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesDisplayCandidateFromRunnerOutput() throws {
        let output = """
        {"NBest":[{"Display":"Ship the release notes today.","Lexical":"ship the release notes today"}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesPredictionAndSentenceRunnerFields() throws {
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"prediction":"今天下午同步发布计划。"}"#),
            "今天下午同步发布计划。"
        )
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"sentences":[{"sentence":"Ship today."},{"sentence":"Confirm QA."}]}"#),
            "Ship today. Confirm QA."
        )
    }

    func testTreatsNoSpeechPlaceholderAsEmpty() throws {
        XCTAssertEqual(try LocalASREngine.parseRunnerOutput(#"{"text":"（无）"}"#), "")
        XCTAssertEqual(try LocalASREngine.parseRunnerOutput(#"{"text":" ( 无 ) "}"#), "")
    }
}
