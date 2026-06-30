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
