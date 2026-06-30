import XCTest
@testable import OpenType

final class TextProcessorFallbackTests: XCTestCase {
    func testSmartFormatDoesNotUsePreparedFallbackByDefault() {
        XCTAssertFalse(TextProcessor.defaultAllowsPreparedFallback)
    }

    func testGeneratedOutputFallsBackOnlyWhenExplicitlyProvided() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanGeneratedOutput("<think>reasoning</think>", inputLanguage: .english),
            ""
        )
        XCTAssertEqual(
            processor.cleanGeneratedOutput(
                "<think>reasoning</think>",
                inputLanguage: .english,
                fallback: "raw transcript"
            ),
            "raw transcript"
        )
    }

    func testGeneratedOutputUsesFinalSectionAfterAnalysisScaffold() {
        let processor = TextProcessor()
        let output = """
        Analysis:
        The user wants a clean status update.

        Final:
        Ship the release notes today.
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .english),
            "Ship the release notes today."
        )
    }

    func testGeneratedOutputUsesTaggedFinalAfterThinkingScaffold() {
        let processor = TextProcessor()
        let output = """
        <analysis>Plan the rewrite.</analysis>
        <final>今天下午同步发布计划。</final>
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .chinese),
            "今天下午同步发布计划。"
        )
    }

    func testGeneratedOutputKeepsAnalysisTextWithoutFinalScaffold() {
        let processor = TextProcessor()
        let output = """
        Analysis:
        This heading is part of the requested text.
        """

        XCTAssertEqual(
            processor.cleanGeneratedOutput(output, inputLanguage: .english),
            output
        )
    }
}
