import XCTest
@testable import OpenType

final class FormattedOutputCleanerTests: XCTestCase {
    func testKeepsOnlyMarkedFinalText() {
        let llmOutput = """
        ---

        **整理后文本：**

        接下来，将整个系统的十八 n 语言 Flow 全部重新做了。
        所有十八 n 文案维护在一个单独的 package 里头，叫 ec at ec 杠 i 幺八 n。

        ---

        **说明：**
        1. **纠错与同音词修正**：
        * 原文“十八 n”在上下文中多次出现。
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            接下来，将整个系统的十八 n 语言 Flow 全部重新做了。
            所有十八 n 文案维护在一个单独的 package 里头，叫 ec at ec 杠 i 幺八 n。
            """
        )
    }

    func testRemovesUnmarkedExplanationSectionAfterFinalText() {
        let llmOutput = """
        接下来，将 i18n 文案迁移到 @ec/i18n。

        说明：
        这里是解释，不应该进入最终输出。
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "接下来，将 i18n 文案迁移到 @ec/i18n。"
        )
    }

    func testKeepsContentStartingWithExplanationHeading() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Explanation:\nThis label is part of the requested text."),
            "Explanation:\nThis label is part of the requested text."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("说明：\n这是用户要求保留的正文标签。"),
            "说明：\n这是用户要求保留的正文标签。"
        )
    }

    func testKeepsSingleLineContentStartingWithFinalTextLabel() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Final text: this label is part of the requested text."),
            "Final text: this label is part of the requested text."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("最终文本：这是用户要求保留的正文标签。"),
            "最终文本：这是用户要求保留的正文标签。"
        )
    }

    func testRemovesInlineFinalTextWrapperWhenExplanationFollows() {
        let llmOutput = """
        Final text: Ship the release notes today.

        Explanation:
        Removed filler words.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testDoesNotInventListBreaks() {
        let llmOutput = "首先确认需求 其次同步时间 最后发出纪要"

        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testRemovesWrappingCodeFence() {
        let llmOutput = """
        Final text:
        ```text
        Ship the release notes today.
        ```

        Explanation:
        Removed filler words.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testRemovesConversationalLeadInLabels() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Here is the final text:\nShip the release notes today."),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("以下是整理后的文本：\n今天下午同步发布计划。"),
            "今天下午同步发布计划。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("こちらが最終テキスト：\n金曜の午後に会議します。"),
            "金曜の午後に会議します。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("다음은 최종 텍스트입니다:\n금요일 오후에 회의합니다."),
            "금요일 오후에 회의합니다."
        )
    }

    func testRemovesJapaneseAndKoreanMarkedFinalText() {
        let japanese = """
        出力：金曜の午後に会議します。

        説明：
        言い直しを整理しました。
        """
        let korean = """
        최종 텍스트:
        금요일 오후에 회의합니다.

        설명:
        말 바꿈을 정리했습니다.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(japanese),
            "金曜の午後に会議します。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean(korean),
            "금요일 오후에 회의합니다."
        )
    }

    func testExtractsStructuredFinalTextJSON() {
        let llmOutput = """
        {"final_text":"Ship the release notes today.","explanation":"Removed filler words."}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsStructuredFinalTextFromFencedJSON() {
        let llmOutput = """
        ```json
        {"result":{"text":"今天下午同步发布计划。"},"reason":"final answer"}
        ```
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsExplicitFinalTextJSONAfterPreamble() {
        let llmOutput = """
        Sure, here is the cleaned result:
        {"final_text":"Ship the release notes today.","reason":"Removed filler words."}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsTypedOutputTextJSONAfterPreamble() {
        let llmOutput = """
        Final response:
        {"type":"output_text","text":"Ship the release notes today."}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsNestedOutputTextWrapper() {
        let llmOutput = """
        {"payload":{"output_text":"今天下午同步发布计划。"}}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "今天下午同步发布计划。"
        )
    }

    func testExtractsResponsesOutputTextArray() {
        let llmOutput = """
        {"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"Ship the release notes today."}]}]}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testExtractsMultipleResponsesOutputTextBlocks() {
        let llmOutput = """
        {"output":[{"type":"message","content":[{"type":"output_text","text":"Ship the release notes."},{"type":"output_text","text":"Then confirm QA."}]}]}
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            Ship the release notes.
            Then confirm QA.
            """
        )
    }

    func testKeepsOrdinaryEmbeddedJSONWithoutExplicitFinalText() {
        let llmOutput = #"The payload is {"text":"Ship the release notes today.","mode":"voice"}."#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }

    func testKeepsOrdinaryJSONWithoutFinalTextField() {
        let llmOutput = #"{"name":"OpenType","mode":"voice"}"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }

    func testKeepsOrdinaryJSONWithAmbiguousTextField() {
        let llmOutput = #"{"text":"Ship the release notes today.","mode":"voice"}"#

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            llmOutput
        )
    }

    func testKeepsContentStartingWithJapaneseOrKoreanExplanationHeading() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("説明：\nこれは本文の見出しです。"),
            "説明：\nこれは本文の見出しです。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("설명:\n이 라벨은 본문입니다."),
            "설명:\n이 라벨은 본문입니다."
        )
    }
}
