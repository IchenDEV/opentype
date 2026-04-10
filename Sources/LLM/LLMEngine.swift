import Foundation
import MLXLLM
import MLXLMCommon
import MLX

actor LLMEngine {
    private var container: ModelContainer?
    private var currentModelID: String?

    func loadModel(id: String, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try validateModelSupport(id: id)
        if currentModelID == id, container != nil { return }

        Log.info("[LLMEngine] loading model: \(id)")
        let t0 = CFAbsoluteTimeGetCurrent()

        let config = ModelConfiguration(id: id)
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { p in
            progress?(p.fractionCompleted)
        }

        currentModelID = id
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[LLMEngine] model loaded in \(String(format: "%.1f", elapsed))s")
    }

    func generate(prompt: String, systemPrompt: String? = nil, maxTokens: Int = 2048) async throws -> String {
        guard let container else {
            throw LLMError.modelNotLoaded
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        let effectivePrompt = Self.applyNoThink(prompt: prompt, modelID: currentModelID)
        let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        let session = ChatSession(container, instructions: systemPrompt, generateParameters: params)
        let result = try await session.respond(to: effectivePrompt)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[LLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    struct BenchmarkResult: Sendable {
        let loadTimeSeconds: Double
        let generateTimeSeconds: Double
        let outputTokenEstimate: Int
        let tokensPerSecond: Double
    }

    func benchmark(modelID: String) async throws -> BenchmarkResult {
        try validateModelSupport(id: modelID)
        let loadT0 = CFAbsoluteTimeGetCurrent()
        try await loadModel(id: modelID)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadT0

        guard let container else { throw LLMError.modelNotLoaded }

        let testPrompt = Self.applyNoThink(
            prompt: "将以下口述内容整理为书面文字：嗯那个就是我觉得我们首先应该把这个方案重新梳理一下然后呢第二个就是要确认一下时间节点第三呢就是把预算也算一下",
            modelID: modelID
        )
        let systemPrompt = "你是语音转文字后处理引擎。直接输出整理后的文本，不要任何解释。"
        let params = GenerateParameters(maxTokens: 512, temperature: 0.3)

        var tokenCount = 0
        let genT0 = CFAbsoluteTimeGetCurrent()

        let _ = try await container.perform { (context: ModelContext) -> String in
            let messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": testPrompt],
            ]
            let lmInput = try await context.processor.prepare(input: .init(messages: messages))
            var output = [Int]()

            let result = try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { tokens in
                tokenCount += tokens.count
                output.append(contentsOf: tokens)
                return output.count >= 256 ? .stop : .more
            }
            return result.output
        }

        let genTime = CFAbsoluteTimeGetCurrent() - genT0
        let tps = genTime > 0 ? Double(tokenCount) / genTime : 0

        Log.info("[LLMEngine] benchmark: \(tokenCount) tokens in \(String(format: "%.1f", genTime))s = \(String(format: "%.1f", tps)) tok/s")

        return BenchmarkResult(
            loadTimeSeconds: loadTime,
            generateTimeSeconds: genTime,
            outputTokenEstimate: tokenCount,
            tokensPerSecond: tps
        )
    }

    var isLoaded: Bool { container != nil }

    func unload() {
        container = nil
        currentModelID = nil
    }

    private func validateModelSupport(id: String) throws {
        if let reason = LLMModelSupport.unsupportedReason(for: id) {
            throw LLMError.unsupportedModel(reason)
        }
    }

    private static func applyNoThink(prompt: String, modelID: String?) -> String {
        guard let id = modelID?.lowercased(), id.contains("qwen3") else { return prompt }
        return "/no_think\n\(prompt)"
    }
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM 模型未加载"
        case .unsupportedModel(let reason): return reason
        }
    }
}
