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

    func testDecodesResolutionNestedInWrapperObject() {
        let output = """
        Final result:
        {
          "result": {
            "action": "rewrite_selection",
            "intent": "summary",
            "replacement": null,
            "confidence": 0.91
          }
        }
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

    func testDecodesPresetIntentWithMetadataAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary","reason":"best fitting edit preset"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"type":"preset","value":"meeting_notes"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesCustomInstructionObjectWithMetadata() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"type":"custom","instruction":"make this warmer for a customer","reason":"contains extra tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.custom("make this warmer for a customer"))
        )
    }

    func testDecodesCaseInsensitiveTopLevelResolutionFields() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"Action":"Replace_Last","Intent":null,"Replacement":{"Text":"ship tomorrow"},"Confidence":{"Score":0.92}}"#
            ),
            .replaceLast("ship tomorrow")
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

    func testDuplicateCaseKeysDoNotBreakStructuredConfidenceDecoding() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"preset":"summary"},"replacement":null,"confidence":{"Score":0.4,"score":0.93}}"#
            ),
            .rewriteSelection(.summary)
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
