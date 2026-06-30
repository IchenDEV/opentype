import XCTest
@testable import OpenType

final class LocalASRTranscriptFinalityTests: XCTestCase {
    func testPrefersFinalRunnerEventOverLaterPartialEvent() throws {
        let output = """
        {"text":"Ship release notes today.","is_final":true}
        {"text":"Ship release","is_final":false}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testRecognizesStringFinalityFields() throws {
        let output = """
        {"text":"Ship release","status":"interim"}
        {"text":"Ship release notes today.","event":"final"}
        {"text":"Ship rel","type":"partial"}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testRecognizesRecognitionStatusFinalityFields() throws {
        let output = """
        {"events":[{"DisplayText":"Ship release","RecognitionStatus":"Intermediate"},{"DisplayText":"Ship release notes today.","RecognitionStatus":"Success"}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testKeepsPartialTextWhenNoFinalTranscriptExists() throws {
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"text":"Ship release","partial":true}"#),
            "Ship release"
        )
    }

    func testPrefersFinalEventInsideRunnerArray() throws {
        let output = """
        [{"text":"Ship release","type":"partial"},{"text":"Ship release notes today.","type":"final"},{"text":"Ship rel","type":"partial"}]
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testPrefersFinalEventInsideRunnerEventContainer() throws {
        let output = """
        {"events":[{"text":"Ship release","type":"partial"},{"text":"Ship release notes today.","type":"final"}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testJoinsFinalSegmentArrayInsteadOfKeepingOnlyLastSegment() throws {
        let output = """
        {"segments":[{"start":0.0,"end":1.0,"text":"Ship the release notes.","is_final":true},{"start":1.0,"end":2.0,"text":"Then confirm QA.","is_final":true}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testParsesNestedMessageAndBodyWrappers() throws {
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"message":{"text":"Ship tomorrow.","status":"completed"}}"#),
            "Ship tomorrow."
        )
        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(#"{"body":{"transcript":"Confirm QA.","is_final":true}}"#),
            "Confirm QA."
        )
    }

    func testStillJoinsUntypedSegmentArrays() throws {
        let output = """
        [{"text":"Ship the release notes."},{"text":"Then confirm QA."}]
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }
}
