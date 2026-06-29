import XCTest
@testable import OpenType

final class LLMStructuredOutputTests: XCTestCase {
    func testFirstJSONObjectDataIgnoresTrailingBraceText() throws {
        let output = """
        result:
        {"text":"ship {alpha} tomorrow","note":"quote: \\"ok\\""}
        trailing {"ignored":true}
        """

        let data = try XCTUnwrap(LLMStructuredOutput.firstJSONObjectData(from: output))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["text"], "ship {alpha} tomorrow")
        XCTAssertEqual(object["note"], #"quote: "ok""#)
    }

    func testFirstJSONObjectDataRejectsUnbalancedOutput() {
        XCTAssertNil(LLMStructuredOutput.firstJSONObjectData(from: #"prefix {"text":"unfinished""#))
    }
}
