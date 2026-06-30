import XCTest
@testable import OpenType

final class RemoteLLMEventStreamTextTests: XCTestCase {
    func testParsesOpenAIEventStreamContentDeltas() throws {
        let response = #"""
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"{\"final_text\":\"Ship "}}]}

        data: {"choices":[{"delta":{"content":"the release notes today.\"}"}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(rawText, #"{"final_text":"Ship the release notes today."}"#)
        XCTAssertEqual(FormattedOutputCleaner.clean(rawText), "Ship the release notes today.")
    }

    func testParsesOpenAIEventStreamToolArgumentDeltas() throws {
        let response = #"""
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":"emit_command","arguments":"{\"action\":\"replace_last\",\"intent\":null,"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91}"}}]}}]}

        data: [DONE]
        """#

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIEventStreamPlainTextDeltas() throws {
        let response = """
        event: message
        data: {"choices":[{"delta":{"content":"Ship the "}}]}

        data: {"choices":[{"delta":{"content":"release notes today."}}]}

        data: [DONE]
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testRejectsEmptyOpenAIEventStream() {
        XCTAssertThrowsError(
            try RemoteLLMResponseText.openAI(from: data("data: [DONE]\n\n"))
        )
    }

    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }
}
