import AVFoundation
import Foundation

struct LocalASRConfiguration: Equatable {
    enum Provider: String, Equatable {
        case qwen3
        case mimo
    }

    static let defaultPythonPath = "python3"
    static let qwen3DefaultModel = "mlx-community/Qwen3-ASR-1.7B-bf16"
    static let mimoDefaultModel = "XiaomiMiMo/MiMo-V2.5-ASR"
    static let mimoTokenizerModel = "XiaomiMiMo/MiMo-Audio-Tokenizer"

    let provider: Provider
    let pythonPath: String
    let modelPath: String
    let tokenizerPath: String
    let repoPath: String

    var isReady: Bool {
        let hasPython = !pythonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModel = Self.pathExists(modelPath)
        switch provider {
        case .qwen3:
            return hasPython && hasModel
        case .mimo:
            return hasPython && hasModel && Self.pathExists(tokenizerPath)
        }
    }

    private static func pathExists(_ path: String) -> Bool {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && FileManager.default.fileExists(atPath: normalized)
    }

    var logName: String {
        switch provider {
        case .qwen3: return "Qwen3ASR"
        case .mimo: return "MiMoASR"
        }
    }
}

final class LocalASREngine: SpeechEngine, @unchecked Sendable {
    private let configuration: LocalASRConfiguration

    init(configuration: LocalASRConfiguration) {
        self.configuration = configuration
    }

    var isReady: Bool { configuration.isReady }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard configuration.isReady else { throw LocalASRError.notConfigured }
        guard let audioURL else { throw LocalASRError.noAudioFile }
        guard let runnerURL = Self.runnerScriptURL() else { throw LocalASRError.runnerMissing }

        let started = CFAbsoluteTimeGetCurrent()
        let output = try await runPythonRunner(runnerURL: runnerURL, audioURL: audioURL, language: language)
        let text = try Self.parseRunnerOutput(output)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[\(configuration.logName)] transcribed \(text.count) chars locally in \(String(format: "%.1f", elapsed))s")
        return text
    }

    private static func runnerScriptURL() -> URL? {
        Bundle.module.url(
            forResource: "local-asr-runner",
            withExtension: "py",
            subdirectory: "Scripts"
        )
    }

    private func runPythonRunner(runnerURL: URL, audioURL: URL, language: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            let pythonPath = configuration.pythonPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if pythonPath.contains("/") {
                process.executableURL = URL(fileURLWithPath: pythonPath)
                process.arguments = runnerArguments(runnerURL: runnerURL, audioURL: audioURL, language: language)
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [pythonPath] + runnerArguments(runnerURL: runnerURL, audioURL: audioURL, language: language)
            }

            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: out, encoding: .utf8) ?? ""
                let errorOutput = String(data: err, encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LocalASRError.processFailed(errorOutput.nonEmpty ?? output))
                    return
                }
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runnerArguments(runnerURL: URL, audioURL: URL, language: String?) -> [String] {
        var args = [
            runnerURL.path,
            "--provider", configuration.provider.rawValue,
            "--audio", audioURL.path,
            "--model", configuration.modelPath
        ]
        if let language {
            args += ["--language", language]
        }
        if !configuration.tokenizerPath.isEmpty {
            args += ["--tokenizer", configuration.tokenizerPath]
        }
        if !configuration.repoPath.isEmpty {
            args += ["--repo", configuration.repoPath]
        }
        return args
    }

    static func parseRunnerOutput(_ output: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalASRError.invalidResponse }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { throw LocalASRError.invalidResponse }
            return normalized
        }

        return trimmed
    }
}

enum LocalASRError: LocalizedError {
    case notConfigured
    case noAudioFile
    case runnerMissing
    case processFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        case .runnerMissing: return L("error.local_asr_runner_missing")
        case .processFailed(let message): return String(format: L("error.local_asr_process_failed"), message)
        case .invalidResponse: return L("error.local_asr_invalid_response")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
