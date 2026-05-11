import Foundation

enum LocalASRRuntime {
    private static let qwenPackage = "qwen3-asr-mlx"
    private static let qwenImport = "qwen3_asr_mlx"
    private static let markerName = ".opentype-runtime-ready"

    static func isReady(for provider: LocalASRConfiguration.Provider) -> Bool {
        switch provider {
        case .qwen3:
            let python = qwenPythonURL()
            return FileManager.default.isExecutableFile(atPath: python.path) &&
                FileManager.default.fileExists(atPath: qwenMarkerURL().path)
        case .mimo:
            return LocalASRConfiguration.resolvePythonPath() != nil
        }
    }

    static func ensurePythonPath(
        for provider: LocalASRConfiguration.Provider,
        preferredPath: String
    ) async throws -> String {
        switch provider {
        case .qwen3:
            return try await ensureQwenRuntime(preferredPath: preferredPath)
        case .mimo:
            guard let python = LocalASRConfiguration.resolvePythonPath(preferredPath: preferredPath) else {
                throw LocalASRRuntimeError.pythonMissing
            }
            return python
        }
    }

    private static func ensureQwenRuntime(preferredPath: String) async throws -> String {
        let runtimeDir = ModelStorage.qwenASRRuntimeDir()
        let runtimePython = qwenPythonURL().path
        if isReady(for: .qwen3) { return runtimePython }

        guard let builderPython = LocalASRConfiguration.resolvePythonPath(preferredPath: preferredPath) else {
            throw LocalASRRuntimeError.pythonMissing
        }

        try? FileManager.default.removeItem(at: runtimeDir)
        try FileManager.default.createDirectory(
            at: runtimeDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await runProcess(executable: builderPython, arguments: ["-m", "venv", runtimeDir.path])
        try await runProcess(
            executable: runtimePython,
            arguments: ["-m", "pip", "install", "--quiet", "--upgrade", "pip", "setuptools", "wheel"]
        )
        try await runProcess(
            executable: runtimePython,
            arguments: ["-m", "pip", "install", "--quiet", qwenPackage]
        )
        try await runProcess(
            executable: runtimePython,
            arguments: ["-c", "import \(qwenImport)"]
        )
        try Data(qwenPackage.utf8).write(to: qwenMarkerURL())
        return runtimePython
    }

    private static func qwenPythonURL() -> URL {
        ModelStorage.qwenASRRuntimeDir().appendingPathComponent("bin/python")
    }

    private static func qwenMarkerURL() -> URL {
        ModelStorage.qwenASRRuntimeDir().appendingPathComponent(markerName)
    }

    private static func runProcess(executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = stderr
            process.terminationHandler = { process in
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LocalASRRuntimeError.processFailed(message ?? ""))
                    return
                }
                continuation.resume(returning: ())
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum LocalASRRuntimeError: LocalizedError {
    case pythonMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            return L("error.local_asr_python_missing")
        case .processFailed(let message):
            return message.isEmpty ? L("error.local_asr_runtime_failed") : message
        }
    }
}
