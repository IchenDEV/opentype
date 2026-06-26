import Foundation

struct DownloadProgressInfo: Equatable, Sendable {
    let fraction: Double
    let elapsedSeconds: TimeInterval
    let completedBytes: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Double

    init(
        fraction: Double,
        elapsedSeconds: TimeInterval,
        completedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double
    ) {
        let completedBytes = max(completedBytes, 0)
        self.fraction = Self.clampFraction(fraction)
        self.elapsedSeconds = elapsedSeconds.isFinite ? max(elapsedSeconds, 0) : 0
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes > 0 ? max(totalBytes, completedBytes) : 0
        self.speedBytesPerSecond = speedBytesPerSecond.isFinite ? max(speedBytesPerSecond, 0) : 0
    }

    var percentText: String {
        "\(Int(clampedFraction * 100))%"
    }

    var elapsedText: String {
        Self.formatDuration(elapsedSeconds)
    }

    var transferredText: String {
        guard completedBytes > 0 else { return "" }
        guard totalBytes > 0 else { return Self.formatBytes(completedBytes) }
        return "\(Self.formatBytes(completedBytes)) / \(Self.formatBytes(totalBytes))"
    }

    var remainingText: String {
        guard totalBytes > 0 else { return L("download.unknown") }
        return Self.formatBytes(max(totalBytes - completedBytes, 0))
    }

    var speedText: String {
        guard speedBytesPerSecond >= 1 else { return L("download.unknown") }
        return "\(Self.formatBytes(Int64(speedBytesPerSecond.rounded())))/s"
    }

    var detailText: String {
        [
            String(format: L("download.elapsed_format"), elapsedText),
            String(format: L("download.progress_format"), percentText),
            String(format: L("download.remaining_format"), remainingText),
            String(format: L("download.speed_format"), speedText),
        ].joined(separator: " · ")
    }

    private var clampedFraction: Double {
        Self.clampFraction(fraction)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
        if bytes >= 1_000 { return String(format: "%.0f KB", Double(bytes) / 1e3) }
        return "\(bytes) B"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

final class DownloadProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let startDate: Date
    private var lastTime: Date
    private var lastBytes: Int64
    private var lastSpeedBytesPerSecond: Double = 0

    init(startDate: Date = Date(), initialBytes: Int64 = 0) {
        self.startDate = startDate
        lastTime = startDate
        lastBytes = max(initialBytes, 0)
    }

    func update(progress: Progress, fraction: Double? = nil) -> DownloadProgressInfo {
        update(
            completedBytes: progress.completedUnitCount,
            totalBytes: progress.totalUnitCount,
            fraction: fraction ?? progress.fractionCompleted
        )
    }

    func update(completedBytes rawCompleted: Int64, totalBytes rawTotal: Int64, fraction: Double? = nil) -> DownloadProgressInfo {
        update(completedBytes: rawCompleted, totalBytes: rawTotal, fraction: fraction, at: Date())
    }

    func update(
        completedBytes rawCompleted: Int64,
        totalBytes rawTotal: Int64,
        fraction: Double? = nil,
        at now: Date
    ) -> DownloadProgressInfo {
        lock.lock()
        defer { lock.unlock() }

        let completedBytes = max(rawCompleted, 0)
        let totalBytes = rawTotal > 0 ? max(rawTotal, completedBytes) : 0
        let sampleElapsed = now.timeIntervalSince(lastTime)
        if sampleElapsed > 0.5 {
            let deltaBytes = completedBytes - lastBytes
            if deltaBytes >= 0 {
                lastSpeedBytesPerSecond = Double(deltaBytes) / sampleElapsed
            } else {
                lastSpeedBytesPerSecond = 0
            }
            lastTime = now
            lastBytes = completedBytes
        }

        let resolvedFraction: Double
        if let fraction {
            resolvedFraction = fraction
        } else if totalBytes > 0 {
            resolvedFraction = Double(completedBytes) / Double(totalBytes)
        } else {
            resolvedFraction = 0
        }

        return DownloadProgressInfo(
            fraction: resolvedFraction,
            elapsedSeconds: now.timeIntervalSince(startDate),
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: lastSpeedBytesPerSecond
        )
    }
}
