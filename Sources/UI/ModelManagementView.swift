import SwiftUI
import AppKit

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @StateObject private var catalog = ModelCatalog.shared

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onUnloadLocalASR: (() -> Void)?

    @State private var customLLMInput = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var selectedModelFamily: ModelCatalog.ModelFamily? = .qwen
    private let benchmarkEngine = LLMEngine()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                storageSection
                Divider()
                preloadSection
                Divider()
                enginePickerSection
                if settings.speechEngine == .whisper {
                    whisperSection
                }
                if settings.speechEngine == .volc {
                    volcSection
                }
                if settings.speechEngine == .qwen3 {
                    qwenASRSection
                }
                if settings.speechEngine == .mimo {
                    mimoASRSection
                }
                Divider()
                llmSection
            }
            .padding(20)
        }
        .onAppear {
            catalog.refreshStatus()
            syncSelectedFamilyFromActiveModel()
        }
        .onChange(of: settings.llmModel) { _, _ in syncSelectedFamilyFromActiveModel() }
        .onChange(of: settings.localASRPythonPath) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.mimoASRRepoPath) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.qwenASRModel) { _, _ in onUnloadLocalASR?() }
        .onChange(of: settings.mimoASRModel) { _, _ in onUnloadLocalASR?() }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("model.storage.title"), systemImage: "externaldrive")
                .font(.headline)

            Text(ModelStorage.root.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button(L("model.storage.choose")) {
                    chooseModelStorageLocation()
                }
                Button(L("model.storage.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ModelStorage.root])
                }
                Button(L("model.storage.reset")) {
                    updateModelStoragePath(ModelStorage.defaultRoot.path)
                }
            }
            .controlSize(.small)
        }
    }

    private var preloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("model.preload.title"), systemImage: "bolt.circle")
                .font(.headline)

            Toggle(L("model.preload.speech"), isOn: $settings.preloadSpeechModelOnLaunch)
                .help(L("model.preload.speech_help"))

            Toggle(L("model.preload.formatting"), isOn: $settings.preloadFormattingModelOnLaunch)
                .help(L("model.preload.formatting_help"))
        }
    }

    // MARK: - Engine Picker

    private var enginePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("model.speech_recognition"), systemImage: "waveform")
                .font(.headline)

            Picker(L("settings.speech_engine"), selection: $settings.speechEngine) {
                ForEach(SpeechEngineType.allCases, id: \.self) { Text($0.label) }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Whisper

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelList(catalog.whisperModels, activeID: settings.whisperModel, type: .whisper)
            Button(L("model.import_local")) {
                importLocalWhisper()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Volc ASR

    private var volcSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("volc.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(L("volc.app_key"), text: $settings.volcAppKey)
                .textFieldStyle(.roundedBorder)
            SecureField(L("volc.access_key"), text: $settings.volcAccessKey)
                .textFieldStyle(.roundedBorder)
            TextField(L("volc.resource_id"), text: $settings.volcResourceId)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Local ASR

    private var qwenASRSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("qwen_asr.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(L("local_asr.python"), text: $settings.localASRPythonPath)
                .textFieldStyle(.roundedBorder)
            modelList(
                catalog.asrModels(for: .qwen3),
                activeID: settings.qwenASRModel,
                type: .asr
            )
        }
    }

    private var mimoASRSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("mimo_asr.config_hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(L("local_asr.python"), text: $settings.localASRPythonPath)
                .textFieldStyle(.roundedBorder)
            TextField(L("local_asr.repo_path"), text: $settings.mimoASRRepoPath)
                .textFieldStyle(.roundedBorder)
            modelList(
                catalog.asrModels(for: .mimo),
                activeID: settings.mimoASRModel,
                type: .asr
            )
        }
    }

    // MARK: - LLM

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("model.text_formatting"), systemImage: "brain")
                .font(.headline)

            if appState.lastFormattingDurationSeconds > 0 {
                HStack(spacing: 8) {
                    Text(L("model.last_formatting"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(String(format: L("model.last_formatting_value"), appState.lastFormattingDurationSeconds))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("model.family.title"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                familyPicker
            }

            if settings.useRemoteLLM {
                RemoteLLMConfigView()
            } else {
                localLLMModelsSection
            }
        }
        .alert(importErrorMessage.isEmpty ? L("model.import_invalid") : L("model.import_failed"), isPresented: $showImportError) {
            Button(L("common.ok")) { }
        } message: {
            if !importErrorMessage.isEmpty { Text(importErrorMessage) }
        }
    }

    @ViewBuilder
    private var localLLMModelsSection: some View {
        if let family = selectedModelFamily {
            let familyModels = catalog.llmModels.filter { $0.family == family }
            if family == .qwen {
                groupedQwenModelList(familyModels, activeID: settings.llmModel)
            } else {
                modelList(familyModels, activeID: settings.llmModel, type: .llm)
            }
        }
        let customModels = catalog.llmModels.filter { $0.family == nil }
        if !customModels.isEmpty {
            Text(L("model.custom_local"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            modelList(customModels, activeID: settings.llmModel, type: .llm)
        }

        HStack(spacing: 8) {
            TextField(L("model.custom_id_placeholder"), text: $customLLMInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            Button(L("common.add")) {
                catalog.addCustomLLM(customLLMInput)
                customLLMInput = ""
            }
            .controlSize(.small)
            .disabled(customLLMInput.isEmpty)
        }
        Button(L("model.import_local")) {
            importLocalLLM()
        }
        .controlSize(.small)
    }

    private func syncSelectedFamilyFromActiveModel() {
        guard !settings.useRemoteLLM else { return }
        if let family = catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family {
            selectedModelFamily = family
        }
    }

    private var familyPicker: some View {
        HStack(spacing: 0) {
            ForEach(ModelCatalog.ModelFamily.allCases, id: \.self) { family in
                familyButton(family)
            }
            remoteFamilyButton
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func familyButton(_ family: ModelCatalog.ModelFamily) -> some View {
        let isSelected = !settings.useRemoteLLM && selectedModelFamily == family

        return Button(action: { selectLocalFamily(family) }) {
            VStack(spacing: 2) {
                Image(systemName: family.icon)
                    .font(.system(size: 14))
                Text(family.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            isSelected
                ? Color.accentColor
                : Color.primary
        )
    }

    private var remoteFamilyButton: some View {
        Button(action: selectRemoteLLM) {
            VStack(spacing: 2) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 14))
                Text(L("model.family.remote"))
                    .font(.system(size: 10, weight: settings.useRemoteLLM ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            settings.useRemoteLLM
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            settings.useRemoteLLM
                ? Color.accentColor
                : Color.primary
        )
    }

    private func selectLocalFamily(_ family: ModelCatalog.ModelFamily) {
        selectedModelFamily = family
        if settings.useRemoteLLM {
            settings.useRemoteLLM = false
            if catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family == family {
                onLoadLLM?()
            }
        }
    }

    private func selectRemoteLLM() {
        if !settings.useRemoteLLM {
            onUnloadLLM?()
            settings.useRemoteLLM = true
        }
    }

    private func chooseModelStorageLocation() {
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

    private func updateModelStoragePath(_ path: String) {
        onUnloadWhisper?()
        onUnloadLLM?()
        onUnloadLocalASR?()
        settings.modelStoragePath = path
        catalog.refreshStatus(recheckingErrors: true)
    }

    private func importLocalWhisper() {
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

    private func importLocalLLM() {
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

    // MARK: - Shared List

    private enum ModelType { case whisper, llm, asr }

    private func qwenSeries(from displayName: String) -> String {
        displayName.components(separatedBy: " ").first ?? displayName
    }

    private func groupedQwenModelList(
        _ models: [ModelCatalog.ModelEntry], activeID: String
    ) -> some View {
        let seriesOrder = ["Qwen2.5", "Qwen3", "Qwen3.5"]
        let grouped = Dictionary(grouping: models) { qwenSeries(from: $0.displayName) }
        let series = seriesOrder.filter { grouped[$0] != nil }

        return VStack(spacing: 8) {
            ForEach(series, id: \.self) { seriesName in
                VStack(alignment: .leading, spacing: 4) {
                    Text(seriesName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                    modelList(grouped[seriesName] ?? [], activeID: activeID, type: .llm)
                }
            }
        }
    }

    private func modelList(
        _ models: [ModelCatalog.ModelEntry], activeID: String, type: ModelType
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                modelRow(model, isActive: model.id == activeID, type: type)
                if index < models.count - 1 { Divider().padding(.horizontal, 10) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Row

    private func modelRow(
        _ model: ModelCatalog.ModelEntry, isActive: Bool, type: ModelType
    ) -> some View {
        HStack(spacing: 10) {
            statusDot(model.status)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    if isActive {
                        Text(L("model.active"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(secondaryText(for: model))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let tps = model.benchmarkTPS {
                        Text(String(format: "%.1f tok/s", tps))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if model.status.isBusy {
                VStack(alignment: .trailing, spacing: 2) {
                    if model.status.isDownloading {
                        ProgressView(value: model.downloadProgress)
                            .frame(width: 60)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if !model.downloadDetail.isEmpty {
                        Text(model.downloadDetail)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if model.cacheSize > 0 {
                Text(ModelCatalog.formatBytes(model.cacheSize))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            rowActions(model, isActive: isActive, type: type)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.04) : .clear)
    }

    @ViewBuilder
    private func rowActions(
        _ model: ModelCatalog.ModelEntry, isActive: Bool, type: ModelType
    ) -> some View {
        if model.status == .notDownloaded || model.status.isError {
            Button(L("common.download")) {
                Task {
                    switch type {
                    case .whisper: await catalog.downloadWhisper(model.id)
                    case .llm: await catalog.downloadLLM(model.id)
                    case .asr: await catalog.downloadASR(model.id)
                    }
                }
            }
            .controlSize(.mini)
        }

        if !isActive && (model.status == .downloaded || model.status == .ready) {
            Button(L("model.use")) {
                switch type {
                case .whisper:
                    onUnloadWhisper?()
                    settings.whisperModel = model.id
                case .llm:
                    onUnloadLLM?()
                    settings.useRemoteLLM = false
                    settings.llmModel = model.id
                    if let family = model.family {
                        selectedModelFamily = family
                    }
                    onLoadLLM?()
                case .asr:
                    onUnloadLocalASR?()
                    switch catalog.asrProvider(for: model.id) {
                    case .qwen3: settings.qwenASRModel = model.id
                    case .mimo: settings.mimoASRModel = model.id
                    case nil: break
                    }
                }
            }
            .controlSize(.mini)
        }

        if type == .llm && (model.status == .downloaded || model.status == .ready) {
            if model.isBenchmarking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Button {
                    Task { await runBenchmark(model.id) }
                } label: {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("model.benchmark"))
            }
        }

        if model.status.canDelete {
            Button(role: .destructive) {
                if isActive {
                    switch type {
                    case .whisper: onUnloadWhisper?()
                    case .llm: onUnloadLLM?()
                    case .asr: onUnloadLocalASR?()
                    }
                }
                switch type {
                case .whisper: catalog.deleteWhisper(model.id)
                case .llm: catalog.deleteLLM(model.id)
                case .asr: catalog.deleteASR(model.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func runBenchmark(_ modelID: String) async {
        guard let idx = catalog.llmModels.firstIndex(where: { $0.id == modelID }) else { return }
        catalog.llmModels[idx].isBenchmarking = true
        catalog.llmModels[idx].benchmarkTPS = nil

        do {
            let result = try await benchmarkEngine.benchmark(modelID: modelID)
            if let i = catalog.llmModels.firstIndex(where: { $0.id == modelID }) {
                catalog.llmModels[i].benchmarkTPS = result.tokensPerSecond
                catalog.llmModels[i].isBenchmarking = false
            }
        } catch {
            Log.error("[Benchmark] failed: \(error.localizedDescription)")
            if let i = catalog.llmModels.firstIndex(where: { $0.id == modelID }) {
                catalog.llmModels[i].isBenchmarking = false
            }
        }
    }

    private func secondaryText(for model: ModelCatalog.ModelEntry) -> String {
        return model.hint
    }

    private func statusDot(_ status: ModelCatalog.ModelStatus) -> some View {
        Group {
            switch status {
            case .notDownloaded:
                Circle().fill(.secondary.opacity(0.3))
            case .downloading, .compiling, .loading:
                ProgressView().controlSize(.mini)
            case .downloaded, .ready:
                Circle().fill(.green)
            case .error:
                Circle().fill(.red)
            }
        }
        .frame(width: 8, height: 8)
    }
}
