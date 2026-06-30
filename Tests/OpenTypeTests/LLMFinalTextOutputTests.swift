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
}
