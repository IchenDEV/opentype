import XCTest
@testable import OpenType

final class LocalASRTranscriptJoinerTests: XCTestCase {
    func testJoinsNumericAndSymbolTokensWithoutAwkwardSpaces() throws {
        let output = """
        {"tokens":[{"token":"Version"},{"token":"1"},{"token":"."},{"token":"2"},{"token":"."},{"token":"3"},{"token":"ships"},{"token":"10"},{"token":":"},{"token":"30"},{"token":"with"},{"token":"99"},{"token":"%"},{"token":"confidence"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Version 1.2.3 ships 10:30 with 99% confidence."
        )
    }

    func testJoinsApostropheTokensInsideLatinWords() throws {
        let output = """
        {"tokens":[{"token":"We"},{"token":"’"},{"token":"ll"},{"token":"ship"},{"token":"OpenType"},{"token":"’"},{"token":"s"},{"token":"update"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "We’ll ship OpenType’s update."
        )
    }

    func testKeepsSentencePunctuationSpacingAfterNumericJoinRules() throws {
        let output = """
        {"tokens":[{"token":"Ship"},{"token":"."},{"token":"Then"},{"token":"confirm"},{"token":"QA"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship. Then confirm QA."
        )
    }
}
