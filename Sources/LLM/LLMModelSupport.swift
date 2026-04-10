import Foundation

enum LLMModelSupport {
    private static let qwen35Fallbacks: [String: String] = [
        "mlx-community/Qwen3.5-0.8B-MLX-4bit": "mlx-community/Qwen3-0.6B-4bit",
        "mlx-community/Qwen3.5-2B-4bit": "mlx-community/Qwen3-1.7B-4bit",
        "mlx-community/Qwen3.5-9B-5bit": "mlx-community/Qwen3-4B-4bit",
        "mlx-community/Qwen3.5-35B-A3B-4bit": "mlx-community/Qwen3-30B-A3B-4bit",
    ]

    static func unsupportedReason(for modelID: String) -> String? {
        guard qwen35Fallbacks[modelID] != nil else { return nil }
        return L("model.unsupported_qwen35")
    }

    static func fallbackModelID(for modelID: String) -> String? {
        qwen35Fallbacks[modelID]
    }
}
