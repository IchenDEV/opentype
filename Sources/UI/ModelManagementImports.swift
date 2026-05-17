import AppKit
import Foundation

extension ModelManagementView {
    func chooseModelStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = ModelStorage.root
        panel.message = L("model.storage.choose")
        if panel.runModal() == .OK, let url = panel.url {
            updateModelStoragePath(url.path)
        }
    }

    func updateModelStoragePath(_ path: String) {
        onUnloadWhisper?()
        onUnloadLLM?()
        onUnloadLocalASR?()
        settings.modelStoragePath = path
        catalog.refreshStatus(recheckingErrors: true)
    }

    func importLocalWhisper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.import_local")
        if panel.runModal() == .OK, let url = panel.url {
            guard isValidWhisperFolder(url) else {
                importErrorMessage = L("model.import_invalid_whisper")
                showImportError = true
                return
            }
            onUnloadWhisper?()
            catalog.addLocalWhisper(url)
        }
    }

    func importLocalLLM() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.import_local")
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) else {
                importErrorMessage = ""
                showImportError = true
                return
            }
            onUnloadLLM?()
            catalog.addLocalLLM(url)
        }
    }

    private func isValidWhisperFolder(_ url: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("\(name).mlmodelc").path) ||
                FileManager.default.fileExists(atPath: url.appendingPathComponent("\(name).mlpackage").path)
        }
    }
}
