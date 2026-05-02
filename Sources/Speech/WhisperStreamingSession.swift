import AVFoundation
import Foundation
import WhisperKit

final class WhisperStreamingSession: @unchecked Sendable {
    private let whisperKit: WhisperKit
    private let partialHandler: @Sendable (String) -> Void
    private let optionsBuilder: () -> DecodingOptions
    private let queue = DispatchQueue(label: "opentype.whisper-stream")

    private static let partialWindowSamples = 15 * 16_000

    private var normalizer: StreamingAudioNormalizer?
    private var samples: [Float] = []
    private var previewAccumulator = StreamingPreviewAccumulator()
    private var latestPreview = ""
    private var pendingWorkItem: DispatchWorkItem?
    private var updateScheduler = StreamingPartialUpdateScheduler()
    private var activeTask: Task<String, Error>?
    private var closed = false
    private var metrics = StreamingSessionMetrics()

    init(
        whisperKit: WhisperKit,
        partialHandler: @escaping @Sendable (String) -> Void,
        optionsBuilder: @escaping () -> DecodingOptions
    ) {
        self.whisperKit = whisperKit
        self.partialHandler = partialHandler
        self.optionsBuilder = optionsBuilder
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async {
            guard !self.closed else { return }
            if self.normalizer == nil {
                self.normalizer = StreamingAudioNormalizer(inputFormat: buffer.format)
            }

            guard let normalizer = self.normalizer else {
                Log.error("[WhisperEngine] failed to create streaming audio normalizer")
                return
            }

            do {
                let chunk = try normalizer.convert(buffer)
                guard !chunk.samples.isEmpty else { return }
                self.metrics.recordBuffer(unitCount: chunk.sampleCount)
                self.samples.append(contentsOf: chunk.samples)
                self.schedulePartialUpdate()
            } catch {
                Log.error("[WhisperEngine] streaming buffer conversion failed: \(error.localizedDescription)")
            }
        }
    }

    func finishLivePreview() async -> StreamingSessionOutcome {
        let task = queue.sync { () -> Task<String, Error>? in
            self.closed = true
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil
            self.updateScheduler.cancelScheduledUpdate()
            return self.activeTask
        }
        _ = try? await task?.value

        return queue.sync {
            StreamingSessionOutcome(
                livePreviewText: self.latestPreview,
                metrics: self.metrics
            )
        }
    }

    func cancel() {
        queue.sync {
            self.closed = true
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil
            self.updateScheduler.cancelScheduledUpdate()
            self.activeTask?.cancel()
            self.activeTask = nil
        }
    }

    private func schedulePartialUpdate() {
        guard updateScheduler.requestSchedule() else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.runScheduledPartialUpdate()
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func runScheduledPartialUpdate() {
        pendingWorkItem = nil
        updateScheduler.markScheduledUpdateFired()
        startPartialTaskIfNeeded()
    }

    private func startPartialTaskIfNeeded() {
        guard !closed, activeTask == nil, samples.count >= WhisperKit.sampleRate else { return }

        let snapshot: [Float]
        if samples.count > Self.partialWindowSamples {
            snapshot = Array(samples.suffix(Self.partialWindowSamples))
        } else {
            snapshot = samples
        }
        let submittedSampleCount = samples.count

        activeTask = Task(priority: .utility) { [weak self, whisperKit, optionsBuilder] in
            let results = try await whisperKit.transcribe(
                audioArray: snapshot,
                decodeOptions: optionsBuilder()
            )
            let text = results
                .compactMap(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await self?.finishPartialTask(text: text, submittedSampleCount: submittedSampleCount)
            return text
        }
    }

    private func finishPartialTask(text: String, submittedSampleCount: Int) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.activeTask = nil
                self.applyPartial(text, emitUpdate: !self.closed)
                if !self.closed, self.samples.count > submittedSampleCount {
                    self.schedulePartialUpdate()
                }
                continuation.resume()
            }
        }
    }

    private func applyPartial(_ text: String, emitUpdate: Bool) {
        guard !text.isEmpty else { return }

        let merged = previewAccumulator.merge(text)
        guard !merged.isEmpty, merged != latestPreview else { return }

        latestPreview = merged
        metrics.markPartial()
        if emitUpdate {
            partialHandler(merged)
        }
    }
}
