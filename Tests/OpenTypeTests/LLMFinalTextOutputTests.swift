import XCTest
@testable import OpenType

final class LLMFinalTextOutputTests: XCTestCase {
    func testExtractsLabeledOutputTextArrayAfterPreamble() {
        let llmOutput = """
        Final response:
        [{"type":"output_text","text":"Ship the release notes."},{"type":"output_text","text":"Then confirm QA."}]
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testKeepsOrdinaryEmbeddedArrayWithoutExplicitFinalText() {
        let llmOutput = #"The payload is [{"text":"Ship the release notes today.","mode":"voice"}]."#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }

    func testExtractsTopLevelTextBlockArray() {
        let llmOutput = """
        [{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testExtractsOpenAIChatTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"choices":[{"message":{"content":[{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]}}]}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testExtractsResponsesTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"id":"resp_1","output":[{"type":"message","content":[{"type":"text","text":"今天下午同步发布计划。"}]}]}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "今天下午同步发布计划。"
        )
    }

    func testKeepsOrdinaryTopLevelArrayWithoutResponseMetadata() {
        let llmOutput = #"[{"text":"Ship the release notes today.","mode":"voice"}]"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }

    func testKeepsOrdinaryOutputStringJSON() {
        let llmOutput = #"{"output":"Ship the release notes today.","mode":"voice"}"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }
}
