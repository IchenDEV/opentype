import XCTest
@testable import OpenType

final class SpokenEditCommandLLMOrderingTests: XCTestCase {
    func testPrefersLaterCommandOverCopiedExampleCommand() {
        let output = """
        Example:
        {"action":"rewrite_selection","intent":"summary","replacement":null,"confidence":0.92}

        Final:
        {"action":"replace_last","intent":null,"replacement":"ship tomorrow","confidence":0.91}
        """

        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(from: output),
            .replaceLast("ship tomorrow")
        )
    }
}
