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
}
