import XCTest
@testable import OpenType

final class FormattedOutputCleanerMetadataTests: XCTestCase {
    func testExtractsAmbiguousTextWhenCertaintyMetadataIsPresent() {
        let llmOutput = """
        {"text":"Ship the release notes today.","certainty":0.91}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }
}
