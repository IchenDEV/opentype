import AppKit
import XCTest
@testable import OpenType

@MainActor
final class PromptAndProcessingTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedInputLanguage = settings.inputLanguage
        let savedLanguageStyle = settings.languageStyle
        let savedEnableMemory = settings.enableMemory
        let savedMemoryWindow = settings.memoryWindowMinutes
        let savedEnableInstantInsert = settings.enableInstantInsert
        let savedEntries = PersonalDictionary.shared.entries
        let savedRules = PersonalDictionary.shared.editRules
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.inputLanguage = .chinese
        settings.languageStyle = .professional
        settings.enableMemory = true
        settings.memoryWindowMinutes = 30
        settings.enableInstantInsert = false
        PersonalDictionary.shared.entries = []
        PersonalDictionary.shared.editRules = []
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.inputLanguage = savedInputLanguage
            settings.languageStyle = savedLanguageStyle
            settings.enableMemory = savedEnableMemory
            settings.memoryWindowMinutes = savedMemoryWindow
            settings.enableInstantInsert = savedEnableInstantInsert
            PersonalDictionary.shared.entries = savedEntries
            PersonalDictionary.shared.editRules = savedRules
        }
        try body()
    }

    func testBuildUserPromptUsesLanguageSpecificWrappers() {
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "嗯 今天开会",
            inputLanguage: .chinese
        ), "以下是语音识别原文，请直接输出整理后的最终文本：\n<<<\n嗯 今天开会\n>>>")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "um hello",
            inputLanguage: .english
        ), "Raw ASR transcript. Output only the final rewritten text:\n<<<\num hello\n>>>")
        XCTAssertEqual(PromptBuilder.buildUserPrompt(
            text: "こんにちは",
            inputLanguage: .japanese
        ), "Raw ASR transcript. Output only the final rewritten text:\n<<<\nこんにちは\n>>>")
    }

    func testSystemPromptIncludesChineseStyleScreenAndMemoryContext() {
        withCleanSettings {
            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "更正式",
                screenContext: "OpenType 设置",
                memoryContext: "刚才提到了快捷键",
                inputLanguage: .chinese
            )

            XCTAssertTrue(prompt.contains("你的任务不是轻度润色"))
            XCTAssertTrue(prompt.contains("风格：专业整理"))
            XCTAssertTrue(prompt.contains("普通说明、状态同步和判断句不要硬改成编号列表"))
            XCTAssertTrue(prompt.contains("只有原文明显是步骤、清单或待办时，才输出 1. 2. 3."))
            XCTAssertTrue(prompt.contains("专业整理补充示例："))
            XCTAssertTrue(prompt.contains("原文：今天主要是把登录问题修掉然后回归一遍没问题的话明天发版"))
            XCTAssertTrue(prompt.contains("屏幕文字，仅供纠错和专有名词参考"))
            XCTAssertTrue(prompt.contains("OpenType 设置"))
            XCTAssertTrue(prompt.contains("最近输入，仅供语境和专有名词参考"))
            XCTAssertTrue(prompt.contains("刚才提到了快捷键"))
            XCTAssertTrue(prompt.contains("原文：嗯那个我们周四，不对，周五下午开会"))
        }
    }

    func testSystemPromptIncludesEnglishStyleScreenAndMemoryContext() {
        withCleanSettings {
            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "professional",
                screenContext: "Meeting notes",
                memoryContext: "previous dictation",
                inputLanguage: .english
            )

            XCTAssertTrue(prompt.contains("Do not lightly polish raw ASR"))
            XCTAssertTrue(prompt.contains("Style: professional cleanup"))
            XCTAssertTrue(prompt.contains("do not force normal explanations or status updates into numbered lists"))
            XCTAssertTrue(prompt.contains("Use 1. 2. 3. only when the raw text is clearly a list"))
            XCTAssertTrue(prompt.contains("Professional cleanup examples:"))
            XCTAssertTrue(prompt.contains("Raw: today the main thing is fixing the login issue and then running regression"))
            XCTAssertTrue(prompt.contains("On-screen text for correction and proper nouns only"))
            XCTAssertTrue(prompt.contains("Meeting notes"))
            XCTAssertTrue(prompt.contains("Recent input for context and proper nouns only"))
            XCTAssertTrue(prompt.contains("previous dictation"))
            XCTAssertTrue(prompt.contains("Raw: um we're meeting Thursday, sorry, Friday afternoon"))
        }
    }

    func testCasualStylePromptStillRequiresCorrection() {
        withCleanSettings {
            let chinese = PromptBuilder.buildSystemPrompt(
                style: .casual,
                stylePrompt: "",
                inputLanguage: .chinese
            )
            XCTAssertTrue(chinese.contains("主动修正明显错别字、同音词"))
            XCTAssertTrue(chinese.contains("不要把明显识别错误原样留下"))
            XCTAssertFalse(chinese.contains("专业整理补充示例："))

            let english = PromptBuilder.buildSystemPrompt(
                style: .casual,
                stylePrompt: "",
                inputLanguage: .english
            )
            XCTAssertTrue(english.contains("actively fix obvious typos, homophones"))
            XCTAssertTrue(english.contains("Do not leave clear ASR errors in place"))
            XCTAssertFalse(english.contains("Professional cleanup examples:"))
        }
    }

    func testCustomSystemPromptOverridesBaseAndStyleOnly() {
        withCleanSettings {
            AppSettings.shared.useCustomSystemPrompt = true
            AppSettings.shared.customSystemPrompt = "Only normalize names."

            let prompt = PromptBuilder.buildSystemPrompt(
                style: .professional,
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

    func testPreCleanRemovesChineseFillers() {
        withCleanSettings {
            let processor = TextProcessor()
            let cleaned = processor.preCleanForFormatting(
                text: "嗯 那个 今天下午开会",
                inputLanguage: .chinese
            )

            XCTAssertEqual(cleaned, "今天下午开会")
        }
    }

    func testPreCleanStructuresOrdinalLists() {
        withCleanSettings {
            let processor = TextProcessor()
            let cleaned = processor.preCleanForFormatting(
                text: "第一先把需求过一下 第二确认时间 第三把预算拉出来",
                inputLanguage: .chinese
            )

            XCTAssertTrue(cleaned.contains("1. 先把需求过一下"))
            XCTAssertTrue(cleaned.contains("2. 确认时间"))
            XCTAssertTrue(cleaned.contains("3. 把预算拉出来"))
        }
    }

    func testFormattingOptionsUseSmallBudgets() {
        withCleanSettings {
            let processor = TextProcessor()

            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .professional).maxTokens, 160)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "中", count: 120), style: .professional).maxTokens, 256)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "长", count: 260), style: .professional).maxTokens, 384)
            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .casual).temperature, 0.08)
            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .professional).temperature, 0.05)
        }
    }

    func testVoicePipelinePolicySkipsMemoryForSmartFormat() {
        withCleanSettings {
            var providerCalls = 0
            let context = VoicePipelinePolicy.memoryContext(for: .processed, settings: AppSettings.shared) { _ in
                providerCalls += 1
                return "should not be used"
            }

            XCTAssertEqual(context, "")
            XCTAssertEqual(providerCalls, 0)
        }
    }

    func testVoicePipelinePolicyKeepsMemoryForVoiceCommand() {
        withCleanSettings {
            var providerCalls = 0
            let context = VoicePipelinePolicy.memoryContext(for: .command, settings: AppSettings.shared) { minutes in
                providerCalls += 1
                return "recent \(minutes)"
            }

            XCTAssertEqual(context, "recent 30")
            XCTAssertEqual(providerCalls, 1)
        }
    }

    func testVoicePipelinePolicyScreenContextGating() {
        XCTAssertFalse(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .processed, useScreenContext: false))
        XCTAssertTrue(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .processed, useScreenContext: true))
        XCTAssertTrue(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .command, useScreenContext: false))
        XCTAssertFalse(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .direct, useScreenContext: true))
    }

    func testDeferredReplacementOnlyAppliesToSmartFormat() {
        XCTAssertTrue(DeferredReplacementPolicy.shouldUseDeferredReplacement(outputMode: .processed, enableInstantInsert: true))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(outputMode: .processed, enableInstantInsert: false))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(outputMode: .direct, enableInstantInsert: true))
        XCTAssertFalse(DeferredReplacementPolicy.shouldUseDeferredReplacement(outputMode: .command, enableInstantInsert: true))
    }

    func testDeferredReplacementDecisionRequiresSameFrontmostApp() throws {
        let replacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: nil,
            message: "formatting",
            createdAt: Date(timeIntervalSince1970: 100),
            expirationInterval: 15
        )
        var readyReplacement = replacement
        readyReplacement.formattedText = "formatted"
        readyReplacement.state = .ready

        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: readyReplacement,
                currentBundleIdentifier: nil,
                now: Date(timeIntervalSince1970: 105)
            ),
            .copy(.missingTarget)
        )

        guard let currentBundleIdentifier = NSRunningApplication.current.bundleIdentifier else {
            throw XCTSkip("Current test process has no bundle identifier")
        }

        readyReplacement = DeferredReplacement(
            rawText: "raw",
            insertedText: "quick",
            targetApp: NSRunningApplication.current,
            message: "formatting",
            createdAt: Date(timeIntervalSince1970: 100),
            expirationInterval: 15
        )
        readyReplacement.formattedText = "formatted"
        readyReplacement.state = .ready

        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: readyReplacement,
                currentBundleIdentifier: "other.app",
                now: Date(timeIntervalSince1970: 105)
            ),
            .copy(.appChanged)
        )
        XCTAssertEqual(
            DeferredReplacementPolicy.decision(
                for: readyReplacement,
                currentBundleIdentifier: currentBundleIdentifier,
                now: Date(timeIntervalSince1970: 116)
            ),
            .copy(.expired)
        )
    }
}
