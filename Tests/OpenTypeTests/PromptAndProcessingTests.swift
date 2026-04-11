import XCTest
@testable import OpenType

@MainActor
final class PromptAndProcessingTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedInputLanguage = settings.inputLanguage
        let savedEntries = PersonalDictionary.shared.entries
        let savedRules = PersonalDictionary.shared.editRules
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.inputLanguage = .chinese
        PersonalDictionary.shared.entries = []
        PersonalDictionary.shared.editRules = []
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.inputLanguage = savedInputLanguage
            PersonalDictionary.shared.entries = savedEntries
            PersonalDictionary.shared.editRules = savedRules
        }
        try body()
    }

    func testBuildUserPromptUsesLanguageSpecificWrappers() {
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "嗯 今天开会",
            inputLanguage: .chinese
        ), "[以下是语音识别原文，请整理为书面文字]\n嗯 今天开会")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "um hello",
            inputLanguage: .english
        ), "[Raw speech transcription below — reformat into written text]\num hello")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "こんにちは",
            inputLanguage: .japanese
        ), "[Raw speech transcription below — reformat into written text]\nこんにちは")
    }

    func testSystemPromptIncludesChineseStyleScreenAndMemoryContext() {
        withCleanSettings {
            let prompt = PromptBuilder.buildSystemPrompt(
                stylePrompt: "更正式",
                screenContext: "OpenType 设置",
                memoryContext: "刚才提到了快捷键",
                inputLanguage: .chinese
            )

            XCTAssertTrue(prompt.contains("你的唯一任务"))
            XCTAssertTrue(prompt.contains("风格要求：更正式"))
            XCTAssertTrue(prompt.contains("以下是用户当前屏幕上的文字"))
            XCTAssertTrue(prompt.contains("OpenType 设置"))
            XCTAssertTrue(prompt.contains("以下是用户最近的输入历史"))
            XCTAssertTrue(prompt.contains("刚才提到了快捷键"))
        }
    }

    func testSystemPromptIncludesEnglishStyleScreenAndMemoryContext() {
        withCleanSettings {
            let prompt = PromptBuilder.buildSystemPrompt(
                stylePrompt: "professional",
                screenContext: "Meeting notes",
                memoryContext: "previous dictation",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.contains("Your ONLY task"))
            XCTAssertTrue(prompt.contains("Style: professional"))
            XCTAssertTrue(prompt.contains("Below is on-screen text"))
            XCTAssertTrue(prompt.contains("Meeting notes"))
            XCTAssertTrue(prompt.contains("Recent input history"))
            XCTAssertTrue(prompt.contains("previous dictation"))
        }
    }

    func testCustomSystemPromptOverridesBaseAndStyleOnly() {
        withCleanSettings {
            AppSettings.shared.useCustomSystemPrompt = true
            AppSettings.shared.customSystemPrompt = "Only normalize names."

            let prompt = PromptBuilder.buildSystemPrompt(
                stylePrompt: "ignored",
                screenContext: "visible text",
                memoryContext: "",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.hasPrefix("Only normalize names."))
            XCTAssertFalse(prompt.contains("Style: ignored"))
            XCTAssertTrue(prompt.contains("visible text"))
        }
    }

    func testCommandSystemPromptUsesLanguageSpecificRules() {
        let chinese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "邮件正文",
            memoryContext: "上一句",
            inputLanguage: .chinese
        )
        XCTAssertTrue(chinese.contains("你是一个语音助手"))
        XCTAssertTrue(chinese.contains("以下是用户当前屏幕上的文字内容"))
        XCTAssertTrue(chinese.contains("邮件正文"))
        XCTAssertTrue(chinese.contains("以下是用户最近的输入历史"))

        let english = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "email body",
            memoryContext: "",
            inputLanguage: .english
        )
        XCTAssertTrue(english.contains("You are a voice assistant"))
        XCTAssertTrue(english.contains("Screen content below"))
        XCTAssertTrue(english.contains("email body"))
        XCTAssertFalse(english.contains("Recent input history"))
    }

    func testPersonalDictionaryReplacementsAndRules() {
        withCleanSettings {
            let dictionary = PersonalDictionary.shared
            dictionary.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true),
                DictionaryEntry(original: "skip me", replacement: "wrong", enabled: false),
            ]
            dictionary.editRules = [
                EditRule(description: "Keep product names exact.", enabled: true),
                EditRule(description: "Disabled rule.", enabled: false),
            ]

            XCTAssertEqual(dictionary.applyReplacements(to: "open type should not skip me"), "OpenType should not skip me")
            XCTAssertEqual(dictionary.activeRulesDescription(), "Keep product names exact.")
        }
    }

    func testBasicCleanAppliesDictionaryAndNormalizesWhitespace() {
        withCleanSettings {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true)
            ]

            let processor = TextProcessor()
            XCTAssertEqual(processor.basicClean(text: "  open type\n\n  is\tfast  "), "OpenType is fast")
        }
    }
}
