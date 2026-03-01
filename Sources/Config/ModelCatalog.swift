import Foundation
import WhisperKit
import MLXLMCommon
import MLXLLM

@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published var whisperModels: [ModelEntry] = []
    @Published var llmModels: [ModelEntry] = []

    private let settings = AppSettings.shared

    /// LLM model family categories
    enum ModelFamily: String, CaseIterable {
        case qwen = "Qwen"
        case gemma = "Gemma"
        case llama = "Llama"

        var icon: String {
            switch self {
            case .qwen: return "q.circle.fill"
            case .gemma: return "g.circle.fill"
            case .llama: return "l.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .qwen: return L("model.family.qwen")
            case .gemma: return L("model.family.gemma")
            case .llama: return L("model.family.llama")
            }
        }
    }

    struct ModelEntry: Identifiable, Equatable {
        let id: String
        let displayName: String
        let hint: String
        let family: ModelFamily?
        var status: ModelStatus = .notDownloaded
        var cacheSize: Int64 = 0
        var downloadProgress: Double = 0
        var downloadDetail: String = ""

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.status == rhs.status &&
            lhs.cacheSize == rhs.cacheSize && lhs.downloadProgress == rhs.downloadProgress
        }
    }

    enum ModelStatus: Equatable {
        case notDownloaded, downloading, compiling, loading, downloaded, ready, error(String)

        var isDownloading: Bool { if case .downloading = self { return true }; return false }
        var isError: Bool { if case .error = self { return true }; return false }
        var isBusy: Bool {
            switch self { case .downloading, .compiling, .loading: return true; default: return false }
        }
        var canDelete: Bool {
            switch self { case .downloaded, .ready, .error: return true; default: return false }
        }
    }

    private static let curatedWhisperVariants = [
        "large-v3", "large-v2", "medium", "small", "distil-large-v3",
    ]

    private init() {
        let rec = WhisperKit.recommendedModels()
        let defaultID = rec.default
        let supported = Set(rec.supported)

        whisperModels = Self.curatedWhisperVariants.compactMap { variant in
            let fullName = rec.supported.first { $0.contains(variant) }
            guard let fullName, supported.contains(fullName) else { return nil }
            return ModelEntry(
                id: fullName,
                displayName: Self.shortenWhisperName(fullName),
                hint: fullName == defaultID ? L("common.recommended") : "",
                family: nil
            )
        }

        if !whisperModels.contains(where: { $0.id == settings.whisperModel }) {
            settings.whisperModel = defaultID
        }

        llmModels = Self.defaultLLMModels.map {
            ModelEntry(id: $0.0, displayName: $0.1, hint: $0.2, family: $0.3)
        }
        refreshStatus()
    }

    static var defaultLLMModels: [(String, String, String, ModelFamily?)] {
        [
            // Qwen Family
            ("mlx-community/Qwen2.5-0.5B-Instruct-4bit", "Qwen2.5 0.5B", L("model.smallest"), .qwen),
            ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "Qwen2.5 1.5B", L("model.balanced"), .qwen),
            ("mlx-community/Qwen2.5-3B-Instruct-4bit", "Qwen2.5 3B", L("model.best_quality"), .qwen),
            ("mlx-community/Qwen3-0.6B-4bit", "Qwen3 0.6B", L("model.qwen3_fast"), .qwen),
            ("mlx-community/Qwen3-1.7B-4bit", "Qwen3 1.7B", L("model.qwen3_balanced"), .qwen),
            ("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", L("model.qwen3_quality"), .qwen),
            ("mlx-community/Qwen3-30B-A3B-4bit", "Qwen3 30B-A3B", L("model.qwen3_moe"), .qwen),

            // Gemma Family (Google)
            ("mlx-community/gemma-3-1b-it-4bit", "Gemma 3 1B", L("model.gemma_fast"), .gemma),
            ("mlx-community/gemma-3-4b-it-4bit", "Gemma 3 4B", L("model.gemma_balanced"), .gemma),
            ("mlx-community/gemma-3-12b-it-4bit", "Gemma 3 12B", L("model.gemma_quality"), .gemma),

            // Llama Family (Meta)
            ("mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit", "Llama 4 Scout", L("model.llama_balanced"), .llama),
            ("mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit", "Llama 4 Maverick", L("model.llama_quality"), .llama),
        ]
    }

    // MARK: - Display Name

    static func shortenWhisperName(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "openai_whisper-", with: "")
        s = s.replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")

        var sizeSuffix = ""
        if let range = s.range(of: "_\\d+MB$", options: .regularExpression) {
            sizeSuffix = " (" + s[range].dropFirst() + ")"
            s = String(s[s.startIndex..<range.lowerBound])
        }
        s = s.replacingOccurrences(of: "_", with: " ")
        return s + sizeSuffix
    }

    // MARK: - Status

    func refreshStatus() {
        for i in whisperModels.indices where !whisperModels[i].status.isBusy {
            let size = whisperVariantSize(whisperModels[i].id)
            whisperModels[i].cacheSize = size
            if whisperModels[i].status != .ready {
                whisperModels[i].status = size > 0 ? .downloaded : .notDownloaded
            }
        }
        for i in llmModels.indices where !llmModels[i].status.isBusy {
            let size = llmRepoSize(llmModels[i].id)
            llmModels[i].cacheSize = size
            if llmModels[i].status != .ready {
                llmModels[i].status = size > 0 ? .downloaded : .notDownloaded
            }
        }
    }

    // MARK: - Whisper Operations

    func downloadWhisper(_ id: String) async {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }),
              !whisperModels[idx].status.isDownloading else { return }

        whisperModels[idx].status = .downloading
        whisperModels[idx].downloadProgress = 0

        do {
            var lastTime = Date()
            var lastBytes: Int64 = 0

            _ = try await WhisperKit.download(
                variant: id,
                downloadBase: Self.whisperDownloadBase,
                progressCallback: { [weak self] p in
                    Task { @MainActor in
                        guard let self, let i = self.whisperModels.firstIndex(where: { $0.id == id }) else { return }
                        let now = Date()
                        let elapsed = now.timeIntervalSince(lastTime)
                        var speedStr = ""
                        if elapsed > 0.5 {
                            let delta = p.completedUnitCount - lastBytes
                            if delta > 0 { speedStr = Self.formatBytes(Int64(Double(delta) / elapsed)) + "/s" }
                            lastTime = now
                            lastBytes = p.completedUnitCount
                        }
                        self.whisperModels[i].downloadProgress = p.fractionCompleted
                        let sz = "\(Self.formatBytes(p.completedUnitCount))/\(Self.formatBytes(p.totalUnitCount))"
                        self.whisperModels[i].downloadDetail = speedStr.isEmpty ? sz : "\(sz) \(speedStr)"
                    }
                }
            )
            whisperModels[idx].status = .downloaded
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
        } catch is CancellationError {
            if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                whisperModels[i].status = .notDownloaded
                whisperModels[i].downloadDetail = ""
            }
        } catch {
            whisperModels[idx].status = .error(error.localizedDescription)
            whisperModels[idx].downloadDetail = ""
        }
    }

    func deleteWhisper(_ id: String) {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        deleteWhisperVariant(id)
        whisperModels[idx].status = .notDownloaded
        whisperModels[idx].cacheSize = 0
    }

    // MARK: - LLM Operations

    func downloadLLM(_ id: String) async {
        guard let idx = llmModels.firstIndex(where: { $0.id == id }),
              !llmModels[idx].status.isDownloading else { return }

        llmModels[idx].status = .downloading
        llmModels[idx].downloadProgress = 0

        do {
            let config = ModelConfiguration(id: id)
            _ = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] p in
                Task { @MainActor in
                    guard let self, let i = self.llmModels.firstIndex(where: { $0.id == id }) else { return }
                    self.llmModels[i].downloadProgress = p.fractionCompleted
                    self.llmModels[i].downloadDetail = "\(Int(p.fractionCompleted * 100))%"
                }
            }
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = .downloaded
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = .notDownloaded
                llmModels[i].downloadDetail = ""
            }
        } catch {
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = .error(error.localizedDescription)
                llmModels[i].downloadDetail = ""
            }
        }
    }

    func deleteLLM(_ id: String) {
        guard let idx = llmModels.firstIndex(where: { $0.id == id }) else { return }
        if let dir = llmRepoDir(id) { try? FileManager.default.removeItem(at: dir) }
        llmModels[idx].status = .notDownloaded
        llmModels[idx].cacheSize = 0
    }

    func addCustomLLM(_ modelID: String) {
        guard !modelID.isEmpty, !llmModels.contains(where: { $0.id == modelID }) else { return }
        let name = modelID.components(separatedBy: "/").last ?? modelID
        llmModels.append(ModelEntry(id: modelID, displayName: name, hint: L("common.custom"), family: nil))
        refreshStatus()
    }

    // MARK: - External Status Updates (called by VoicePipeline)

    func updateWhisperStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard let i = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        whisperModels[i].status = status
        whisperModels[i].downloadDetail = detail
        if status == .ready || status == .downloaded {
            whisperModels[i].cacheSize = whisperVariantSize(id)
        }
    }

    func updateLLMStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard let i = llmModels.firstIndex(where: { $0.id == id }) else { return }
        llmModels[i].status = status
        llmModels[i].downloadDetail = detail
        if status == .ready || status == .downloaded {
            llmModels[i].cacheSize = llmRepoSize(id)
        }
    }

    // MARK: - Cache Utilities

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
        if bytes >= 1_000 { return String(format: "%.0f KB", Double(bytes) / 1e3) }
        return "\(bytes) B"
    }

    /// Custom download base for WhisperKit — ~/Library/Application Support/OpenType/huggingface/
    static let whisperDownloadBase: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("OpenType/huggingface")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let hubModelsBase: URL = {
        whisperDownloadBase.appendingPathComponent("models")
    }()

    // MARK: Whisper cache

    private func whisperVariantDir(_ variant: String) -> URL {
        Self.hubModelsBase
            .appendingPathComponent("argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
    }

    private func whisperVariantSize(_ variant: String) -> Int64 {
        let dir = whisperVariantDir(variant)
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        return Self.directorySize(at: dir)
    }

    /// Returns true if the Whisper variant is already downloaded (skip download progress UI).
    func isWhisperDownloaded(_ variant: String) -> Bool {
        whisperVariantSize(variant) > 0
    }

    private func deleteWhisperVariant(_ variant: String) {
        let dir = whisperVariantDir(variant)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: LLM cache — ~/Library/Caches/models/<org>/<model>/
    // LLMModelFactory uses defaultHubApi with downloadBase = ~/Library/Caches/

    private static let llmCacheBase: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("models")
    }()

    private func llmRepoDir(_ modelID: String) -> URL? {
        let dir = Self.llmCacheBase.appendingPathComponent(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    private func llmRepoSize(_ modelID: String) -> Int64 {
        guard let dir = llmRepoDir(modelID) else { return 0 }
        return Self.directorySize(at: dir)
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let sz = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(sz)
            }
        }
        return total
    }
}
