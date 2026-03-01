import Foundation
import MLXLLM
import MLXLMCommon
import MLX

actor LLMEngine {
    private var container: ModelContainer?
    private var currentModelID: String?

    func loadModel(id: String, progress: (@Sendable (Double) -> Void)? = nil) async throws {
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

        let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        let session = ChatSession(container, instructions: systemPrompt, generateParameters: params)
        let result = try await session.respond(to: prompt)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[LLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    var isLoaded: Bool { container != nil }
}

enum LLMError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM 模型未加载"
        }
    }
}
