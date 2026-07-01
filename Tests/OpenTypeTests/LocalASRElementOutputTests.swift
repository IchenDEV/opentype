import XCTest
@testable import OpenType

final class LocalASRElementOutputTests: XCTestCase {
    func testParsesMonologueElementsWithTypedValues() throws {
        let output = """
        {"monologues":[{"speaker":0,"elements":[{"type":"text","value":"Ship"},{"type":"text","value":"the release notes"},{"type":"punct","value":"."}]}]}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes."
        )
    }

    func testKeepsLogShapedTypedElementPayloads() throws {
        let output = """
        {"level":"info","payload":{"elements":[{"type":"word","value":"Confirm"},{"type":"word","value":"QA"},{"type":"punctuation","value":"."}]}}
        {"level":"info","message":"Loading local ASR model"}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Confirm QA."
        )
    }

    func testIgnoresUntypedMetadataValue() throws {
        let output = """
        {"value":"Loading local ASR model","text":"Ship tomorrow."}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship tomorrow."
        )
    }
}
