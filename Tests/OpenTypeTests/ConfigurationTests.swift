import Foundation
import XCTest
@testable import OpenType

final class ConfigurationTests: XCTestCase {
    func testRemoteProviderDefaultsMatchExpectedAPIs() {
        XCTAssertEqual(RemoteProvider.openai.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(RemoteProvider.openai.defaultModel, "gpt-4.1-mini")
        XCTAssertEqual(RemoteProvider.openai.apiFormat, .openai)
        XCTAssertNil(RemoteProvider.openai.defaultApiVersion)

        XCTAssertEqual(RemoteProvider.claude.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(RemoteProvider.claude.defaultModel, "claude-sonnet-4-6-20251001")
        XCTAssertEqual(RemoteProvider.claude.apiFormat, .anthropic)
        XCTAssertEqual(RemoteProvider.claude.defaultApiVersion, "2023-06-01")

        XCTAssertEqual(RemoteProvider.gemini.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(RemoteProvider.openrouter.defaultModel, "google/gemini-2.5-flash")
        XCTAssertEqual(RemoteProvider.siliconflow.defaultBaseURL, "https://api.siliconflow.cn/v1")
        XCTAssertEqual(RemoteProvider.doubao.defaultBaseURL, "https://ark.cn-beijing.volces.com/api/v3")
        XCTAssertEqual(RemoteProvider.bailian.defaultBaseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(RemoteProvider.minimax.defaultBaseURL, "https://api.minimax.chat/v1")
        XCTAssertEqual(RemoteProvider.minimaxGlobal.defaultBaseURL, "https://api.minimaxi.chat/v1")
    }

    func testRemoteProviderAllCasesAreStableAndIdentifiable() {
        XCTAssertEqual(RemoteProvider.allCases.map(\.id), [
            "custom", "openai", "claude", "gemini", "openrouter",
            "siliconflow", "doubao", "bailian", "minimax", "minimaxGlobal",
        ])
        XCTAssertTrue(RemoteProvider.allCases.dropFirst().allSatisfy { !$0.defaultBaseURL.isEmpty })
        XCTAssertTrue(RemoteProvider.allCases.dropFirst().allSatisfy { !$0.defaultModel.isEmpty })
    }

    func testInputLanguageMetadata() {
        XCTAssertNil(InputLanguage.auto.whisperCode)
        XCTAssertEqual(InputLanguage.chinese.whisperCode, "zh")
        XCTAssertEqual(InputLanguage.english.whisperCode, "en")
        XCTAssertEqual(InputLanguage.japanese.whisperCode, "ja")
        XCTAssertEqual(InputLanguage.korean.whisperCode, "ko")
        XCTAssertEqual(InputLanguage.cantonese.whisperCode, "yue")

        XCTAssertEqual(InputLanguage.auto.localeIdentifier, "zh-CN")
        XCTAssertEqual(InputLanguage.chinese.localeIdentifier, "zh-CN")
        XCTAssertEqual(InputLanguage.english.localeIdentifier, "en-US")
        XCTAssertEqual(InputLanguage.japanese.localeIdentifier, "ja-JP")
        XCTAssertEqual(InputLanguage.korean.localeIdentifier, "ko-KR")
        XCTAssertEqual(InputLanguage.cantonese.localeIdentifier, "zh-HK")
    }

    func testHistoryRetentionIntervals() {
        XCTAssertNil(HistoryRetention.forever.timeInterval)
        XCTAssertEqual(HistoryRetention.threeDays.timeInterval, TimeInterval(3 * 24 * 3600))
        XCTAssertEqual(HistoryRetention.sevenDays.timeInterval, TimeInterval(7 * 24 * 3600))
        XCTAssertEqual(HistoryRetention.oneMonth.timeInterval, TimeInterval(30 * 24 * 3600))
    }

    func testMenuBarIconSymbols() {
        XCTAssertEqual(MenuBarIcon.mic.symbolName, "mic.fill")
        XCTAssertEqual(MenuBarIcon.waveform.symbolName, "waveform")
        XCTAssertEqual(MenuBarIcon.bubble.symbolName, "bubble.left.fill")
    }

    func testLanguageStyleStaticMetadata() {
        XCTAssertEqual(LanguageStyle.professional.icon, "list.number")
        XCTAssertEqual(LanguageStyle.casual.icon, "bubble.left")
        XCTAssertEqual(LanguageStyle.custom.icon, "slider.horizontal.3")
    }

    @MainActor
    func testRecommendedLocalModelRemainsListed() {
        XCTAssertTrue(ModelCatalog.defaultLLMModels.contains { $0.0 == "mlx-community/Qwen3.5-2B-4bit" })
    }

    func testUILanguageDisplayNames() {
        XCTAssertEqual(UILanguage.chinese.displayName, "中文")
        XCTAssertEqual(UILanguage.english.displayName, "English")
    }

    func testInstantInsertDefaultsOff() {
        XCTAssertFalse(AppSettings.shared.enableInstantInsert)
    }
}
