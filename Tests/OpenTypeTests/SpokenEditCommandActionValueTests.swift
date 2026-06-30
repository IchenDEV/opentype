import XCTest
@testable import OpenType

final class SpokenEditCommandActionValueTests: XCTestCase {
    func testDecodesTopLevelCommandTypeActionAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"command_type":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.summary)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"operationType":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
    }

    func testDecodesStructuredCommandTypeActionAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"command_type":"replace_selection","reason":"final command"},"intent":null,"replacement":"new customer note","confidence":0.91}"#
            ),
            .replaceSelection("new customer note")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":{"operationType":"rewrite_last","confidence":0.91},"intent":"formal","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.formal)
        )
    }

    func testDecodesStructuredActionTargetPairs() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"replace","target":"last_insertion","intent":null,"replacement":"ship tomorrow","confidence":0.91}"#
            ),
            .replaceLast("ship tomorrow")
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"operation":"rewrite","scope":{"type":"selection"},"intent":"meeting_notes","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"delete","object":"selected_text","intent":null,"replacement":null,"confidence":0.91}"#
            ),
            .deleteSelection
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"command":"undo","edit_target":"previous_insertion","intent":null,"replacement":null,"confidence":0.91}"#
            ),
            .undoLastInsertion
        )
    }
}
