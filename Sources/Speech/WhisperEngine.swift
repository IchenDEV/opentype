import Foundation
import WhisperKit
import CoreML

final class WhisperEngine: SpeechEngine {
    private var whisperKit: WhisperKit?
    private let modelName: String?
    private(set) var isReady = false
    private(set) var isLoading = false
    private var loadError: String?

    init(modelName: String = "large-v3") {
        self.modelName = modelName.isEmpty ? nil : modelName
    }

    struct DownloadProgress {
        var fraction: Double
        var completedBytes: Int64
        var totalBytes: Int64
        var speedBytesPerSec: Double
        var stage: Stage

        enum Stage: String {
            case downloading = "下载中"
            case compiling = "编译模型"
            case loading = "加载模型"
            case done = "完成"
        }

        var sizeText: String {
            guard totalBytes > 0 else { return "" }
            return "\(Self.formatBytes(completedBytes)) / \(Self.formatBytes(totalBytes))"
        }

        var speedText: String {
            guard speedBytesPerSec > 0 else { return "" }
            return Self.formatBytes(Int64(speedBytesPerSec)) + "/s"
        }

        static func formatBytes(_ bytes: Int64) -> String {
            if bytes >= 1_000_000_000 {
                return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
            } else if bytes >= 1_000_000 {
                return String(format: "%.1f MB", Double(bytes) / 1_000_000)
            } else if bytes >= 1_000 {
                return String(format: "%.0f KB", Double(bytes) / 1_000)
            }
            return "\(bytes) B"
        }
    }

    func loadModel(progress: @escaping (DownloadProgress) -> Void) async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true

        do {
            let recommended = WhisperKit.recommendedModels()
            var selectedModel = modelName ?? recommended.default

            if !recommended.supported.contains(selectedModel) {
                if let match = recommended.supported.first(where: {
                    $0.localizedCaseInsensitiveContains(selectedModel)
                }) {
                    Log.info("[WhisperEngine] '\(selectedModel)' not in list, matched: \(match)")
                    selectedModel = match
                } else {
                    Log.info("[WhisperEngine] '\(selectedModel)' not in list, fallback: \(recommended.default)")
                    selectedModel = recommended.default
                }
            }
            Log.info("[WhisperEngine] using model: \(selectedModel)")

            progress(dp(0.02, stage: .downloading))

            var lastTime = Date()
            var lastBytes: Int64 = 0

            let folder: URL
            do {
                folder = try await WhisperKit.download(
                    variant: selectedModel,
                    downloadBase: ModelCatalog.whisperDownloadBase,
                    progressCallback: { p in
                        let now = Date()
                        let elapsed = now.timeIntervalSince(lastTime)
                        let completed = p.completedUnitCount
                        let total = p.totalUnitCount

                        var speed: Double = 0
                        if elapsed > 0.5 {
                            let deltaBytes = completed - lastBytes
                            if deltaBytes > 0 { speed = Double(deltaBytes) / elapsed }
                            lastTime = now
                            lastBytes = completed
                        }

                        let frac = 0.02 + p.fractionCompleted * 0.58
                        progress(DownloadProgress(
                            fraction: frac, completedBytes: completed,
                            totalBytes: total, speedBytesPerSec: speed, stage: .downloading
                        ))
                    }
                )
            } catch {
                isLoading = false
                throw WhisperError.downloadFailed(error.localizedDescription)
            }
            Log.info("[WhisperEngine] download complete")

            progress(dp(0.62, stage: .compiling))

            let compute = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuAndGPU
            )

            let kit: WhisperKit
            do {
                kit = try await WhisperKit(
                    WhisperKitConfig(
                        modelFolder: folder.path,
                        computeOptions: compute,
                        verbose: false,
                        prewarm: false,
                        load: false
                    )
                )

                progress(dp(0.70, stage: .compiling))
                try await kit.prewarmModels()
            } catch {
                isLoading = false
                throw WhisperError.compileFailed(error.localizedDescription)
            }

            progress(dp(0.85, stage: .loading))
            do {
                try await kit.loadModels()
            } catch {
                isLoading = false
                throw WhisperError.loadFailed(error.localizedDescription)
            }

            whisperKit = kit
            isReady = true
            isLoading = false
            loadError = nil
            progress(dp(1.0, stage: .done))
            Log.info("[WhisperEngine] model loaded")
        } catch let error as WhisperError {
            loadError = error.localizedDescription
            isReady = false
            Log.error("[WhisperEngine] \(error.localizedDescription)")
            throw error
        } catch {
            loadError = error.localizedDescription
            isReady = false
            isLoading = false
            Log.error("[WhisperEngine] model load failed: \(error.localizedDescription)")
            throw error
        }
    }

    func startListening() {}

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let whisperKit, isReady else {
            throw WhisperError.modelNotLoaded(loadError ?? "未知原因")
        }
        guard let url = audioURL else {
            throw WhisperError.noAudioFile
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        let options = DecodingOptions(
            language: language,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )

        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: options)
        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[WhisperEngine] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    func unload() {
        whisperKit = nil
        isReady = false
        isLoading = false
        loadError = nil
    }

    private func dp(_ fraction: Double, stage: DownloadProgress.Stage) -> DownloadProgress {
        DownloadProgress(fraction: fraction, completedBytes: 0, totalBytes: 0, speedBytesPerSec: 0, stage: stage)
    }
}

enum WhisperError: LocalizedError {
    case modelNotLoaded(String)
    case noAudioFile
    case downloadFailed(String)
    case compileFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let detail): return String(format: L("error.whisper_not_loaded"), detail)
        case .noAudioFile: return L("error.no_audio")
        case .downloadFailed(let detail): return String(format: L("error.download_failed"), detail)
        case .compileFailed(let detail): return String(format: L("error.compile_failed"), detail)
        case .loadFailed(let detail): return String(format: L("error.load_failed"), detail)
        }
    }
}
