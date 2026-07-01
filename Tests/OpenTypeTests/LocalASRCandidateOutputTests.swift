import XCTest
@testable import OpenType

final class LocalASRCandidateOutputTests: XCTestCase {
    func testSelectsHighestConfidenceCandidateFromRunnerOutput() throws {
        let output = """
        {"candidates":[{"text":"Skip the release notes today.","confidence":0.42},{"text":"Ship the release notes today.","confidence":0.91}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testParsesBeamTokenCandidatesFromNestedResult() throws {
        let output = """
        {"result":{"beams":[{"tokens":[{"token":"Skip"},{"token":"today"},{"token":"."}],"score":42},{"tokens":[{"token":"Ship"},{"token":"today"},{"token":"."}],"score":93}]}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship today."
        )
    }

    func testKeepsLogShapedCandidatePayloads() throws {
        let output = """
        {"level":"info","payload":{"candidates":[{"transcript":"Ship tomorrow.","confidence":0.91}]}}
        {"level":"info","message":"Loading local ASR model"}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship tomorrow."
        )
    }
}
