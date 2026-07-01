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

    func testExtractsTypedFinalTextContentPayload() {
        let llmOutput = """
        Final response:
        {"type":"final_text","content":"Ship the release notes today."}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsCamelAndKebabTypedFinalTextPayloads() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean(#"{"type":"finalText","content":"Ship the release notes today."}"#),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean(#"{"type":"formatted-text","value":"今天下午同步发布计划。"}"#),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsValueEnvelopeInsideTypedFinalText() {
        let llmOutput = """
        {"type":"output_text","text":{"value":"Ship the release notes today.","annotations":[]}}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
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

    func testExtractsOpenAIDeltaFinalTextFromWholeResponse() {
        let llmOutput = #"""
        {"choices":[{"delta":{"content":"{\"final_text\":\"Ship the release notes today.\"}"}}]}
        """#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testKeepsPlainOpenAIDeltaWithoutExplicitFinalText() {
        let llmOutput = #"{"choices":[{"delta":{"content":"Ship the release notes today."}}]}"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
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

    func testExtractsAnthropicTextBlocksFromWholeResponse() {
        let llmOutput = """
        {"content":[{"type":"thinking","thinking":"internal reasoning"},{"type":"text","text":"Ship the release notes."},{"type":"text","text":"Then confirm QA."}]}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
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

    func testKeepsOrdinaryContentArrayJSON() {
        let llmOutput = #"{"content":[{"text":"Ship the release notes today.","mode":"voice"}],"mode":"voice"}"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }
}
