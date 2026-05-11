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
    static let mimoRepositoryURL = "https://github.com/XiaomiMiMo/MiMo-V2.5-ASR.git"

    let provider: Provider
    let pythonPath: String
    let modelPath: String
    let tokenizerPath: String
    let repoPath: String

    var isReady: Bool {
        hasRequiredFiles && LocalASRRuntime.isReady(for: provider)
    }

    var hasRequiredFiles: Bool {
        let hasModel = Self.pathExists(modelPath)
        switch provider {
        case .qwen3:
            return hasModel
        case .mimo:
            return hasModel && Self.pathExists(tokenizerPath) && Self.pathExists(repoPath)
        }
    }

    private static func pathExists(_ path: String) -> Bool {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && FileManager.default.fileExists(atPath: normalized)
    }

    static func resolvePythonPath(preferredPath: String = "") -> String? {
        let preferred = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var commands = ["python3.13", "python3.12", "python3.11", "python3.10", "python3", "python"]
        if !preferred.isEmpty && preferred != defaultPythonPath {
            commands.insert(preferred, at: 0)
        }
        for command in commands {
            if let path = resolvePythonCandidate(command) { return path }
        }
        return nil
    }

    private static func resolvePythonCandidate(_ candidate: String) -> String? {
        guard !candidate.isEmpty else { return nil }
        if candidate.contains("/") {
            let expanded = NSString(string: candidate).expandingTildeInPath
            return isUsablePython(at: expanded) ? expanded : nil
        }
        return findExecutable(named: candidate).first(where: { isUsablePython(at: $0) })
    }

    private static func findExecutable(named name: String) -> [String] {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let envDirs = envPath.split(separator: ":").map(String.init)
        let commonDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let localDirs = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        var seen = Set<String>()
        return (envDirs + localDirs + commonDirs).compactMap { dir in
            let path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            guard seen.insert(path).inserted else { return nil }
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
    }

    private static func isUsablePython(at path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0 else { return false }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        let version = (String(data: out + err, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = parsePythonVersion(version) else { return false }
        return parsed.major == 3 && parsed.minor >= 10
    }

    private static func parsePythonVersion(_ output: String) -> (major: Int, minor: Int)? {
        let parts = output
            .replacingOccurrences(of: "Python ", with: "")
            .split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return nil }
        return (major, minor)
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
        guard configuration.hasRequiredFiles else { throw LocalASRError.notConfigured }
        let pythonPath = try await LocalASRRuntime.ensurePythonPath(
            for: configuration.provider,
            preferredPath: configuration.pythonPath
        )
        guard let audioURL else { throw LocalASRError.noAudioFile }
        guard let runnerURL = Self.runnerScriptURL() else { throw LocalASRError.runnerMissing }

        let started = CFAbsoluteTimeGetCurrent()
        let output = try await runPythonRunner(
            runnerURL: runnerURL,
            audioURL: audioURL,
            language: language,
            pythonPath: pythonPath
        )
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

    private func runPythonRunner(
        runnerURL: URL,
        audioURL: URL,
        language: String?,
        pythonPath: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = runnerArguments(runnerURL: runnerURL, audioURL: audioURL, language: language)

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
    case pythonMissing
    case processFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        case .runnerMissing: return L("error.local_asr_runner_missing")
        case .pythonMissing: return L("error.local_asr_python_missing")
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
