import XCTest
@testable import OpenType

final class SpokenEditCommandIntentValueTests: XCTestCase {
    func testDecodesStyleIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"style":"formal","reason":"requested tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.formal)
        )
    }

    func testDecodesFormatIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","intent":{"format":"bullet_points","note":"list output"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.bulletList)
        )
    }

    func testDecodesCategoryIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"category":"meeting_summary"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.meetingNotes)
        )
    }

    func testDecodesTopLevelFormatAndCategoryAsIntent() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","format":"numbered_points","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.numberedList)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_last","category":"main_points","replacement":null,"confidence":0.91}"#
            ),
            .rewriteLast(.keyPoints)
        )
    }

    func testDecodesTargetStyleIntentObjectAsPreset() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":{"target_style":"casual","reason":"requested tone"},"replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.casual)
        )
    }

    func testDecodesCommonPresetAliases() {
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"action_item","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.actionItems)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"reply_english","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.replyInEnglish)
        )
        XCTAssertEqual(
            SpokenEditCommandLLMResolver.command(
                from: #"{"action":"rewrite_selection","intent":"translate_chinese","replacement":null,"confidence":0.91}"#
            ),
            .rewriteSelection(.translateToChinese)
        )
    }
}
