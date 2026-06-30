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

    func testJoinsEmailAndMentionTokensWithoutSpaces() throws {
        let output = """
        {"tokens":[{"token":"Send"},{"token":"to"},{"token":"support"},{"token":"@"},{"token":"example"},{"token":"."},{"token":"com"},{"token":"and"},{"token":"tag"},{"token":"#"},{"token":"release"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Send to support@example.com and tag #release."
        )
    }

    func testJoinsURLPathAndShortcutTokensWithoutSpaces() throws {
        let output = """
        {"tokens":[{"token":"Open"},{"token":"https"},{"token":":"},{"token":"/"},{"token":"/"},{"token":"github"},{"token":"."},{"token":"com"},{"token":"/"},{"token":"IchenDEV"},{"token":"/"},{"token":"opentype"},{"token":"with"},{"token":"Command"},{"token":"+"},{"token":"Shift"},{"token":"+"},{"token":"P"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Open https://github.com/IchenDEV/opentype with Command+Shift+P."
        )
    }

    func testStripsSentencePieceAndBPESpaceMarkers() throws {
        let output = """
        {"tokens":[{"token":"▁OpenType"},{"token":"▁ships"},{"token":"Ġtoday"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "OpenType ships today."
        )
    }

    func testJoinsSentencePieceAndBPEContinuationPieces() throws {
        let output = """
        {"tokens":[{"token":"▁Open"},{"token":"Type"},{"token":"Ġships"},{"token":"▁today"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "OpenType ships today."
        )
    }

    func testJoinsWordPieceContinuationTokens() throws {
        let output = """
        {"tokens":[{"token":"Open"},{"token":"##Type"},{"token":"trans"},{"token":"##cription"},{"token":"works"},{"token":"."}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "OpenType transcription works."
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
