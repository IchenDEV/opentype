import XCTest
@testable import OpenType

final class LocalASRJSONLinesOutputTests: XCTestCase {
    func testJoinsJSONLineTranscriptSegmentsWithoutFinalityMetadata() throws {
        let output = """
        {"text":"Ship the release notes."}
        {"text":"Then confirm QA."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testSkipsRunnerJSONLogLinesWhenJoiningTranscriptSegments() throws {
        let output = """
        {"level":"info","message":"Loading local ASR model"}
        {"text":"今天下午同步发布计划。"}
        {"text":"然后确认 QA。"}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "今天下午同步发布计划。然后确认 QA。"
        )
    }

    func testKeepsFinalityMetadataOnExistingBestCandidatePath() throws {
        let output = """
        {"type":"partial","text":"Ship the"}
        {"type":"final","text":"Ship the release notes today."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testJoinsFinalJSONLineTranscriptSegments() throws {
        let output = """
        {"type":"final","text":"Ship the release notes."}
        {"type":"final","text":"Then confirm QA."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testKeepsLatestCumulativeFinalJSONLineTranscript() throws {
        let output = """
        {"type":"final","text":"Ship"}
        {"type":"final","text":"Ship today"}
        {"type":"final","text":"Ship today."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship today."
        )
    }

    func testParsesDataPrefixedJSONLineTranscriptSegments() throws {
        let output = """
        event: transcript
        data: {"text":"OpenType ships"}
        data: {"text":"today."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "OpenType ships today."
        )
    }
}
