import XCTest
@testable import OpenType

final class LocalASRStableWrapperTests: XCTestCase {
    func testPrefersStableTranscriptWrapperOverUnstableWrapper() throws {
        let output = """
        {"stable":{"text":"Ship the release notes today."},"unstable":{"text":"Ship rel"}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship the release notes today."
        )
    }

    func testPrefersFinalResultWrapperOverPartialWrapper() throws {
        let output = """
        {"partial":{"text":"Ship release"},"finalResult":{"alternatives":[{"transcript":"Ship release notes today.","confidence":0.91}]}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testKeepsPlainTextWhenStableIsOnlyMetadata() throws {
        let output = """
        {"text":"Ship release notes today.","stable":true}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Ship release notes today."
        )
    }

    func testKeepsLogShapedStableTranscriptPayload() throws {
        let output = """
        {"severity":"info","stable":{"text":"Confirm QA after the build."}}
        """

        XCTAssertEqual(
            try LocalASREngine.parseRunnerOutput(output),
            "Confirm QA after the build."
        )
    }
}
