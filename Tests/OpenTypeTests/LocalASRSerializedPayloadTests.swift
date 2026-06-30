import XCTest
@testable import OpenType

final class LocalASRSerializedPayloadTests: XCTestCase {
    func testParsesSerializedJSONTranscriptWrapper() throws {
        let output = #"""
        {"result":"{\"text\":\"Ship tomorrow.\"}"}
        """#

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship tomorrow."
        )
    }

    func testParsesSerializedJSONSegmentWrapper() throws {
        let output = #"""
        {"data":"{\"segments\":[{\"text\":\"Ship the release notes.\"},{\"text\":\"Then confirm QA.\"}]}"}
        """#

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes. Then confirm QA."
        )
    }

    func testKeepsSerializedJSONWithoutTranscriptSignal() throws {
        let output = #"""
        {"payload":"{\"foo\":\"bar\"}"}
        """#

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            #"{"foo":"bar"}"#
        )
    }
}
