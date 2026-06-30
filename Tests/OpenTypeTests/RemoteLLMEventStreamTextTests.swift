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

    func testParsesAnthropicEventStreamTextDeltas() throws {
        let response = #"""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"final_text\":\"Ship "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the release notes today.\"}"}}

        event: message_stop
        data: {"type":"message_stop"}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(rawText, #"{"final_text":"Ship the release notes today."}"#)
        XCTAssertEqual(FormattedOutputCleaner.clean(rawText), "Ship the release notes today.")
    }

    func testParsesAnthropicEventStreamToolInputDeltas() throws {
        let response = #"""
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"emit_command","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"action\":\"replace_last\",\"intent\":null,"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"replacement\":\"ship tomorrow\",\"confidence\":0.91"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}
        """#

        let rawText = try RemoteLLMResponseText.anthropic(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesAnthropicEventStreamPlainTextDeltas() throws {
        let response = """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Ship the "}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"release notes today."}}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(response)),
            "Ship the release notes today."
        )
    }

    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }
}
