import Foundation

struct StreamingSessionMetrics: Equatable {
    var receivedBufferCount = 0
    var capturedUnitCount = 0
    var partialUpdateCount = 0
    var startedAt = Date()
    var lastPartialAt: Date?

    var hasCapturedAudio: Bool {
        capturedUnitCount > 0
    }

    mutating func recordBuffer(unitCount: Int) {
        guard unitCount > 0 else { return }
        receivedBufferCount += 1
        capturedUnitCount += unitCount
    }

    mutating func markPartial(at date: Date = Date()) {
        partialUpdateCount += 1
        lastPartialAt = date
    }
}

struct StreamingSessionOutcome: Equatable {
    let livePreviewText: String
    let metrics: StreamingSessionMetrics
}

struct StreamingPartialUpdateScheduler: Equatable {
    private var hasScheduledUpdate = false

    mutating func requestSchedule() -> Bool {
        guard !hasScheduledUpdate else { return false }
        hasScheduledUpdate = true
        return true
    }

    mutating func markScheduledUpdateFired() {
        hasScheduledUpdate = false
    }

    mutating func cancelScheduledUpdate() {
        hasScheduledUpdate = false
    }
}

enum StreamingTranscriptResolver {
    static func resolveFinalTranscript(
        engineName: String,
        audioURL: URL?,
        livePreviewText: String,
        metrics: StreamingSessionMetrics,
        unitLabel: String,
        preferLivePreview: Bool = false,
        transcribeFromFile: @escaping () async throws -> String
    ) async throws -> String {
        let elapsed = Date().timeIntervalSince(metrics.startedAt)
        let partialAgeText: String
        if let lastPartialAt = metrics.lastPartialAt {
            partialAgeText = String(format: "%.2fs", Date().timeIntervalSince(lastPartialAt))
        } else {
            partialAgeText = "n/a"
        }

        Log.info(
            "[\(engineName)] streaming summary: buffers=\(metrics.receivedBufferCount) " +
            "\(unitLabel)=\(metrics.capturedUnitCount) partials=\(metrics.partialUpdateCount) " +
            "elapsed=\(String(format: "%.2fs", elapsed)) lastPartialAgo=\(partialAgeText)"
        )

        if !metrics.hasCapturedAudio {
            Log.error("[\(engineName)] streaming session captured 0 \(unitLabel)")
        }

        let trimmedPreview = livePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferLivePreview, !trimmedPreview.isEmpty, metrics.partialUpdateCount > 0 {
            Log.info("[\(engineName)] using streaming preview as final transcript")
            return trimmedPreview
        }

        guard audioURL != nil else {
            Log.info("[\(engineName)] no recorded audio file available, using live preview fallback")
            return trimmedPreview
        }

        let finalText = try await transcribeFromFile()
        if finalText.isEmpty, !trimmedPreview.isEmpty {
            Log.info("[\(engineName)] recorded-audio transcription was empty even though live preview had content")
        }
        return finalText
    }
}

final class StreamingPreviewAccumulator {
    private static let minimumMeaningfulOverlap = 2

    private(set) var previewText = ""
    private var latestWindow = ""

    func merge(_ rawText: String) -> String {
        let windowText = Self.normalize(rawText)
        guard !windowText.isEmpty else { return previewText }
        defer { latestWindow = windowText }

        if previewText.isEmpty {
            previewText = windowText
            return previewText
        }

        if windowText == latestWindow {
            return previewText
        }

        if previewText.hasSuffix(latestWindow) {
            let sharedPrefix = Self.commonPrefixCount(latestWindow, windowText)
            let requiredPrefix = max(Self.minimumMeaningfulOverlap, min(latestWindow.count, windowText.count) / 2)
            if sharedPrefix >= requiredPrefix {
                previewText.removeLast(latestWindow.count)
                previewText += windowText
                return previewText
            }
        }

        previewText = Self.merge(existing: previewText, incoming: windowText)
        return previewText
    }

    static func merge(existing: String, incoming: String) -> String {
        let current = normalize(existing)
        let next = normalize(incoming)

        guard !current.isEmpty else { return next }
        guard !next.isEmpty else { return current }

        if current == next || current.hasSuffix(next) || current.contains(next) {
            return current
        }

        if next.hasPrefix(current) {
            return next
        }

        let overlap = largestOverlapCount(existing: current, incoming: next)
        if overlap > 0 {
            return current + next.dropFirst(overlap)
        }

        return join(current, next)
    }

    private static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func largestOverlapCount(existing: String, incoming: String) -> Int {
        let maxOverlap = min(existing.count, incoming.count)
        guard maxOverlap >= minimumMeaningfulOverlap else { return 0 }

        for count in stride(from: maxOverlap, through: minimumMeaningfulOverlap, by: -1) {
            if existing.suffix(count) == incoming.prefix(count) {
                return count
            }
        }

        return 0
    }

    private static func commonPrefixCount(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        guard let lhsLast = lhs.last, let rhsFirst = rhs.first else {
            return lhs + rhs
        }

        if lhsLast.isLetterOrNumberLike && rhsFirst.isLetterOrNumberLike {
            return lhs + " " + rhs
        }

        return lhs + rhs
    }
}

private extension Character {
    var isLetterOrNumberLike: Bool {
        unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}
