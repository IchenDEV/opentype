import XCTest
@testable import OpenType

final class SpokenEditCommandReplacementValueTests: XCTestCase {
    func testDecodesFinalTextReplacementObject() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"final_text":"ship tomorrow"},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesUpdatedAndCorrectedReplacementObjects() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_selection","intent":null,"replacement":{"updated_text":"new customer note","reason":"clearer"},"confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"correctedText":"ship tomorrow at 3 PM","language":"en"},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow at 3 PM")
        )
    }

    func testDecodesPreviousCurrentReplacementObject() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"previous":"ship today","current":"ship tomorrow"},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesContentWrappedReplacementObject() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_last","intent":null,"replacement":{"content":{"value":"ship tomorrow"},"type":"text","annotations":[]},"confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace_selection","intent":null,"replacement":{"output":"new customer note","reason":"adapter payload"},"confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
    }
}
