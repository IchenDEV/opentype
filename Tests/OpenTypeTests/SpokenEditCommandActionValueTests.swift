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
}
