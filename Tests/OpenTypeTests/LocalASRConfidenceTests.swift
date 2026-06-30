import XCTest
@testable import OpenType

final class LocalASRConfidenceTests: XCTestCase {
    func testSelectsAlternativeWithConfidenceValueEnvelope() throws {
        let output = """
        {"alternatives":[{"transcript":"Skip the release notes today.","confidence":{"value":"42%"}},{"transcript":"Ship the release notes today.","confidence":{"value":"0.93"}}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testSelectsAlternativeWithNormalizedConfidenceEnvelope() throws {
        let output = """
        {"hypotheses":[{"transcript":"Skip the release notes today.","confidence":{"normalizedValue":0.41}},{"transcript":"Ship the release notes today.","confidence":{"normalized_value":91}}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }
}
