import SwiftUI
import AppKit

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @StateObject private var catalog = ModelCatalog.shared

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?

    @State private var customLLMInput = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var remoteTestMessage: String?
    @State private var remoteTestSuccess: Bool?
    @State private var isTestingRemote = false
    @State private var selectedModelFamily: ModelCatalog.ModelFamily? = .qwen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                enginePickerSection
                if settings.speechEngine == .whisper {
                    whisperSection
                }
                Divider()
                llmSection
                Divider()
                remoteSection
            }
            .padding(20)
        }
        .onAppear { catalog.refreshStatus() }
    }

    // MARK: - Engine Picker

    private var enginePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("model.speech_recognition"), systemImage: "waveform")
                .font(.headline)

            Picker(L("settings.speech_engine"), selection: $settings.speechEngine) {
                ForEach(SpeechEngineType.allCases, id: \.self) { Text($0.label) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Whisper

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelList(catalog.whisperModels, activeID: settings.whisperModel, type: .whisper)
        }
    }

    // MARK: - LLM

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("model.text_formatting"), systemImage: "brain")
                .font(.headline)

            // Model Family Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(L("model.family.title"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                familyPicker
            }

            // Models list for selected family
            if let family = selectedModelFamily {
                modelList(
                    catalog.llmModels.filter { $0.family == family },
                    activeID: settings.llmModel,
                    type: .llm
                )
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
                importLocalModel()
            }
            .controlSize(.small)
        }
        .alert(importErrorMessage.isEmpty ? L("model.import_invalid") : L("model.import_failed"), isPresented: $showImportError) {
            Button(L("common.ok")) { }
        } message: {
            if !importErrorMessage.isEmpty { Text(importErrorMessage) }
        }
    }

    private var familyPicker: some View {
        HStack(spacing: 0) {
            ForEach(ModelCatalog.ModelFamily.allCases, id: \.self) { family in
                familyButton(family)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func familyButton(_ family: ModelCatalog.ModelFamily) -> some View {
        Button(action: { selectedModelFamily = family }) {
            VStack(spacing: 2) {
                Image(systemName: family.icon)
                    .font(.system(size: 14))
                Text(family.rawValue)
                    .font(.system(size: 10, weight: selectedModelFamily == family ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selectedModelFamily == family
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            selectedModelFamily == family
                ? Color.accentColor
                : Color.primary
        )
    }

    private func importLocalModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("model.import_local")
        if panel.runModal() == .OK, let url = panel.url {
            let configURL = url.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                importErrorMessage = ""
                showImportError = true
                return
            }
            let folderName = url.lastPathComponent
            let localBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("models/local")
            try? FileManager.default.createDirectory(at: localBase, withIntermediateDirectories: true)
            let destURL = localBase.appendingPathComponent(folderName)
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.createSymbolicLink(at: destURL, withDestinationURL: url)
                catalog.addCustomLLM("local/\(folderName)")
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }

    // MARK: - Remote LLM

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("remote.title"), systemImage: "cloud")
                .font(.headline)

            Toggle(L("remote.use_remote"), isOn: $settings.useRemoteLLM)

            if settings.useRemoteLLM {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker(L("remote.provider"), selection: $settings.remoteProvider) {
                            ForEach(RemoteProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(settings.remoteProvider.apiFormat == .anthropic ? "Anthropic API" : "OpenAI API")
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: settings.remoteProvider) { _, newProvider in
                        settings.remoteBaseURL = newProvider.defaultBaseURL
                        settings.remoteModel = newProvider.defaultModel
                    }

                    SecureField(L("remote.api_key"), text: $settings.remoteAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField(L("remote.base_url"), text: $settings.remoteBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField(L("remote.model"), text: $settings.remoteModel)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button(L("remote.test")) {
                            Task { await testRemoteConnection() }
                        }
                        .controlSize(.small)
                        .disabled(isTestingRemote || settings.remoteAPIKey.isEmpty || settings.remoteBaseURL.isEmpty || settings.remoteModel.isEmpty)

                        if isTestingRemote {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if let msg = remoteTestMessage {
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundStyle((remoteTestSuccess ?? false) ? .green : .red)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private func testRemoteConnection() async {
        remoteTestMessage = nil
        remoteTestSuccess = nil
        isTestingRemote = true
        defer { isTestingRemote = false }

        let client = RemoteLLMClient()
        do {
            _ = try await client.generate(
                prompt: "Hi",
                systemPrompt: nil,
                baseURL: settings.remoteBaseURL,
                apiKey: settings.remoteAPIKey,
                model: settings.remoteModel,
                provider: settings.remoteProvider,
                maxTokens: 10
            )
            remoteTestMessage = L("remote.test_success")
            remoteTestSuccess = true
        } catch {
            remoteTestMessage = "\(L("remote.test_failed")): \(error.localizedDescription)"
            remoteTestSuccess = false
        }
    }

    // MARK: - Shared List

    private enum ModelType { case whisper, llm }

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
                Text(model.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
                    settings.llmModel = model.id
                }
            }
            .controlSize(.mini)
        }

        if model.status.canDelete {
            Button(role: .destructive) {
                if isActive {
                    switch type {
                    case .whisper: onUnloadWhisper?()
                    case .llm: onUnloadLLM?()
                    }
                }
                switch type {
                case .whisper: catalog.deleteWhisper(model.id)
                case .llm: catalog.deleteLLM(model.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
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
