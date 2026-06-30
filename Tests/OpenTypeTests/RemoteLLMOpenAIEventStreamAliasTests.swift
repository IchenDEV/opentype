import XCTest
@testable import OpenType

final class RemoteLLMOpenAIEventStreamAliasTests: XCTestCase {
    func testParsesTypedContentDeltaBlocks() throws {
        let response = #"""
        data: {"choices":[{"delta":{"content":[{"type":"output_text_delta","delta":"{\"final_text\":\"Ship "}]}}]}

        data: {"choices":[{"delta":{"content":{"type":"output_text_delta","delta":"the release notes today.\"}"}}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: Data(response.utf8))

        XCTAssertEqual(rawText, #"{"final_text":"Ship the release notes today."}"#)
        XCTAssertEqual(FormattedOutputCleaner.clean(rawText), "Ship the release notes today.")
    }

    func testParsesTypedTextDeltaBlocksWithTextAlias() throws {
        let response = #"""
        data: {"choices":[{"delta":{"content":{"type":"text_delta","text":"Ship the "}}}]}

        data: {"choices":[{"delta":{"content":{"type":"text_delta","text":"release notes today."}}}]}

        data: [DONE]
        """#

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: Data(response.utf8)),
            "Ship the release notes today."
        )
    }
}
