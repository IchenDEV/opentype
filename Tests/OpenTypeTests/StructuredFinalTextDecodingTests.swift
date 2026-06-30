import XCTest
@testable import OpenType

final class StructuredFinalTextDecodingTests: XCTestCase {
    func testExtractsDoubleEncodedStructuredFinalTextJSON() {
        let llmOutput = #"""
        {"final_text":"{\"final_text\":\"Ship the release notes today.\"}","explanation":"adapter returned JSON as a string"}
        """#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsFencedJSONInsideStructuredFinalText() {
        let llmOutput = #"""
        {"payload":{"output_text":"```json\n{\"final_text\":\"今天下午同步发布计划。\"}\n```"}}
        """#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "今天下午同步发布计划。"
        )
    }

    func testKeepsLiteralJSONInsideStructuredFinalTextWhenItHasNoFinalPayload() {
        let llmOutput = #"""
        {"final_text":"{\"name\":\"OpenType\",\"mode\":\"voice\"}","explanation":"user asked for JSON"}
        """#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            #"{"name":"OpenType","mode":"voice"}"#
        )
    }
}
