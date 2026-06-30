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

    func testJSONObjectDataCandidatesReturnBalancedObjectsInOrder() throws {
        let output = #"noise {"ignored":true} then {"action":"none","confidence":0}"#

        let candidates = LLMStructuredOutput.jsonObjectDataCandidates(from: output)

        XCTAssertEqual(candidates.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[0]) as? [String: Bool])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: candidates[1]) as? [String: Any])
        XCTAssertEqual(first["ignored"], true)
        XCTAssertEqual(second["action"] as? String, "none")
    }
}
