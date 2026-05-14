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
