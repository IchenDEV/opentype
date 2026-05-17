import AppKit
import XCTest
@testable import OpenType

@MainActor
final class VoicePipelinePolicyTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedEnableMemory = settings.enableMemory
        let savedMemoryWindow = settings.memoryWindowMinutes
        let savedEnableInstantInsert = settings.enableInstantInsert
        settings.enableMemory = true
        settings.memoryWindowMinutes = 30
        settings.enableInstantInsert = false
        defer {
            settings.enableMemory = savedEnableMemory
            settings.memoryWindowMinutes = savedMemoryWindow
            settings.enableInstantInsert = savedEnableInstantInsert
        }
        try body()
    }

    private func audioActivity(rms: Float, frames: Int = 16_000) -> AudioCaptureActivity {
        var activity = AudioCaptureActivity()
        activity.record(rms: rms, frameCount: frames)
        return activity
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

    func testTranscriptionSanitizerRejectsEmptyAndPunctuation() {
        XCTAssertNil(TranscriptionSanitizer.prepare(""))
        XCTAssertNil(TranscriptionSanitizer.prepare("   "))
        XCTAssertNil(TranscriptionSanitizer.prepare("。。。"))
        XCTAssertNil(TranscriptionSanitizer.prepare("...!?"))
        XCTAssertNil(TranscriptionSanitizer.prepare("  -- ,, "))
    }

    func testTranscriptionSanitizerRejectsLowContentWhenAudioEvidenceIsWeak() {
        let weakActivity = audioActivity(rms: 0.002)

        XCTAssertNil(TranscriptionSanitizer.prepare("嗯", audioActivity: weakActivity))
        XCTAssertNil(TranscriptionSanitizer.prepare("Um.", audioActivity: weakActivity))
        XCTAssertNil(TranscriptionSanitizer.prepare(" OK ", audioActivity: weakActivity))
        XCTAssertEqual(TranscriptionSanitizer.prepare("OK", audioActivity: audioActivity(rms: 0.03)), "OK")
    }

    func testTranscriptionSanitizerRejectsCommonArtifacts() {
        XCTAssertNil(TranscriptionSanitizer.prepare("字幕志愿者:某某某"))
        XCTAssertNil(TranscriptionSanitizer.prepare("请不吝点赞订阅转发打赏"))
        XCTAssertNil(TranscriptionSanitizer.prepare("Thanks for watching!"))
        XCTAssertNil(TranscriptionSanitizer.prepare("Please subscribe to my channel"))
        XCTAssertNil(TranscriptionSanitizer.prepare("I'm sorry, I can't assist with that request."))
    }

    func testTranscriptionSanitizerAcceptsRealSpeech() {
        XCTAssertEqual(TranscriptionSanitizer.prepare("你好世界"), "你好世界")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Hello world"), "Hello world")
        XCTAssertEqual(TranscriptionSanitizer.prepare("帮我整理一下这段话"), "帮我整理一下这段话")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Write a function that adds two numbers"), "Write a function that adds two numbers")
    }

    func testTranscriptionSanitizerCollapsesSameRecordingDuplicate() {
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("帮我整理一下这段话 帮我整理一下这段话"),
            "帮我整理一下这段话"
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("Write a short release note. Write a short release note."),
            "Write a short release note."
        )
        XCTAssertEqual(TranscriptionSanitizer.prepare("yes yes"), "yes yes")
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
