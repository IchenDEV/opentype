import XCTest
@testable import OpenType

final class SpokenEditCommandLLMRobustnessTests: XCTestCase {
    func testSkipsLeadingNonResolutionJSONObject() {
        let output = """
        Example payload:
        {"ignored":true}

        Final:
        {"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .rewriteSelection(.summary)
        )
    }

    func testDecodesSingleValueObjectIntentAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"Preset":"meeting_notes"},"replacement":null,"confidence":{"Score":0.92}}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesStructuredIntentDetailsAsCustomInstruction() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: """
                {
                  "action": "rewrite_selection",
                  "intent": {
                    "audience": "customer",
                    "task": "turn this into an apology with one concrete next step",
                    "tone": "warm"
                  },
                  "replacement": null,
                  "confidence": {"value": "93%"}
                }
                """
            ),
            .rewriteSelection(.custom("audience: customer; task: turn this into an apology with one concrete next step; tone: warm"))
        )
    }

    func testDecodesStructuredReplacementText() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"text":"ship tomorrow at 3 PM"},"confidence":{"confidence":0.9}}"#
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
    }

    func testKeepsStructuredLowConfidenceAsNone() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.resolution(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary"},"replacement":null,"confidence":{"score":0.62}}"#
            ),
            .some(.none)
        )
    }
}
