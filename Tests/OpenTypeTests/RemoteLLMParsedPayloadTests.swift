import XCTest
@testable import OpenType

final class RemoteLLMParsedPayloadTests: XCTestCase {
    func testParsesOpenAIParsedMessageObject() throws {
        let response = """
        {"choices":[{"message":{"content":null,"parsed":{"final_text":"Ship the release notes today."}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(FormattedOutputCleaner.clean(rawText), "Ship the release notes today.")
    }

    func testParsesOpenAIParsedCommandObject() throws {
        let response = """
        {"choices":[{"message":{"content":null,"parsed":{"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}}}]}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: rawText),
            .replaceLast("ship tomorrow")
        )
    }

    func testParsesOpenAIResponsesOutputParsedObject() throws {
        let response = """
        {"id":"resp_1","output_parsed":{"final_text":"今天下午同步发布计划。"}}
        """

        let rawText = try RemoteLLMResponseText.openAI(from: data(response))

        XCTAssertEqual(FormattedOutputCleaner.clean(rawText), "今天下午同步发布计划。")
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }
}
