import XCTest
@testable import OpenType

final class TranscriptionSanitizerTests: XCTestCase {
    func testCollapsesRepeatedTranscriptMoreThanTwice() {
        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Write a short release note. Write a short release note. Write a short release note."
            ),
            "Write a short release note."
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("帮我整理一下这段话 帮我整理一下这段话 帮我整理一下这段话"),
            "帮我整理一下这段话"
        )
    }

    func testKeepsShortRepeatedUtterances() {
        XCTAssertEqual(TranscriptionSanitizer.prepare("yes yes yes"), "yes yes yes")
        XCTAssertEqual(TranscriptionSanitizer.prepare("OK OK OK"), "OK OK OK")
    }
}
