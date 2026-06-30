import XCTest
@testable import OpenType

final class LLMResolutionFieldAliasTests: XCTestCase {
    func testDecodesTypeAndConfidenceScoreAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"type":"rewrite_selection","intent":"summary","replacement":null,"confidence_score":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
    }

    func testDecodesNameCertaintyAndFinalTextReplacementAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"name":"replace_last","intent":null,"final_text":"ship tomorrow","certainty":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesContentReplacementAlias() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action_type":"replace_selection","intent":null,"content":"new customer note","confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
    }
}
