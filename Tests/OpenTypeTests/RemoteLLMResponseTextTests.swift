import XCTest
@testable import OpenType

final class RemoteLLMResponseTextTests: XCTestCase {
    func testParsesOpenAIStringContent() throws {
        let response = """
        {"choices":[{"message":{"content":"  Ship the release notes today.  "}}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIContentBlocks() throws {
        let response = """
        {
          "choices": [
            {
              "message": {
                "content": [
                  {"type":"text","text":"Ship the release notes."},
                  {"type":"image_url","image_url":{"url":"ignored"}},
                  {"type":"output_text","text":"Then confirm QA."}
                ]
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testParsesNestedOpenAITextBlock() throws {
        let response = """
        {"choices":[{"message":{"content":[{"type":"text","text":{"value":"今天下午同步发布计划。"}}]}}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesLaterOpenAIChoiceWhenFirstChoiceHasNoText() throws {
        let response = """
        {
          "choices": [
            {"message":{"content":""}},
            {"message":{"content":[{"type":"text","text":"Ship the release notes today."}]}}
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAITextChoiceFallback() throws {
        let response = """
        {"choices":[{"text":"  Ship the release notes today.  "}]}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes today."
        )
    }

    func testParsesOpenAIResponsesOutputBlocks() throws {
        let response = """
        {
          "id": "resp_1",
          "output": [
            {
              "type": "message",
              "content": [
                {"type":"output_text","text":"Ship the release notes."},
                {"type":"image_url","image_url":{"url":"ignored"}},
                {"type":"output_text","text":"Then confirm QA."}
              ]
            }
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testParsesOpenAIResponsesOutputTextShortcut() throws {
        let response = """
        {"id":"resp_1","output_text":"  今天下午同步发布计划。  "}
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.openAI(from: data(response)),
            "今天下午同步发布计划。"
        )
    }

    func testParsesAllAnthropicTextBlocks() throws {
        let response = """
        {
          "content": [
            {"type":"thinking","thinking":"internal reasoning"},
            {"type":"text","text":"Ship the release notes."},
            {"type":"tool_use","name":"ignored"},
            {"type":"text","text":"Then confirm QA."}
          ]
        }
        """

        XCTAssertEqual(
            try RemoteLLMResponseText.anthropic(from: data(response)),
            "Ship the release notes.\nThen confirm QA."
        )
    }

    func testRejectsResponsesWithoutText() {
        XCTAssertThrowsError(
            try RemoteLLMResponseText.openAI(from: data(#"{"choices":[{"message":{"content":[]}}]}"#))
        )
        XCTAssertThrowsError(
            try RemoteLLMResponseText.anthropic(from: data(#"{"content":[{"type":"thinking","thinking":"no text"}]}"#))
        )
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
