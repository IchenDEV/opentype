import Foundation

enum ModelStorage {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType/huggingface")
    }

    static var root: URL {
        let path = AppSettings.shared.modelStoragePath
        let url = path.isEmpty ? defaultRoot : URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var huggingFaceBase: URL {
        root
    }

    static var hubModelsBase: URL {
        huggingFaceBase.appendingPathComponent("models")
    }

    static func whisperVariantDir(_ variant: String) -> URL {
        hubModelsBase
            .appendingPathComponent("argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
    }

    static func llmRepoDir(_ modelID: String) -> URL? {
        if let local = localLLMURL(modelID) { return local }
        let dir = hubModelsBase.appendingPathComponent(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func localWhisperURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localWhisperModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func localLLMURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localLLMModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func directorySize(at url: URL) -> Int64 {
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

    static func makeLocalID(prefix: String, folderName: String, existing: Set<String>) -> String {
        let cleanName = folderName.isEmpty ? "model" : folderName
        let base = "local/\(prefix)-\(cleanName)"
        guard existing.contains(base) else { return base }
        for n in 2...999 {
            let candidate = "\(base)-\(n)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base)-\(UUID().uuidString.prefix(8))"
    }
}
