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

    func testJoinsFinalResultsWithAlternativesInsteadOfKeepingOnlyLastResult() throws {
        let output = """
        {"results":[{"isFinal":true,"alternatives":[{"transcript":"Ship the release notes.","confidence":0.91}]},{"isFinal":true,"alternatives":[{"transcript":"Then confirm QA.","confidence":0.92}]}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testPrefersDeepgramStyleSpeechFinalChannelAlternative() throws {
        let output = """
        {"results":[{"speech_final":false,"channel":{"alternatives":[{"transcript":"Ship release","confidence":0.81}]}},{"speech_final":true,"channel":{"alternatives":[{"transcript":"Ship release notes today.","confidence":0.94}]}}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testRecognizesEndpointFinalityBooleanAliases() throws {
        let output = """
        {"events":[{"text":"Ship release","is_eos":false},{"text":"Ship release notes today.","sentence_end":true},{"text":"Ship rel","utterance_end":false}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testRecognizesCompoundTranscriptFinalityStatuses() throws {
        let output = """
        {"events":[{"message_type":"PartialTranscript","text":"Ship release"},{"message_type":"FinalTranscript","text":"Ship release notes today."},{"message_type":"PartialResult","text":"Ship rel"}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testRecognizesEndpointFinalityStringStatuses() throws {
        let output = """
        {"events":[{"event":"partial","text":"Ship release"},{"event":"UtteranceEnd","text":"Ship release notes today."},{"event":"partial","text":"Ship rel"}]}
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
