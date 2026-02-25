import SwiftUI

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @StateObject private var catalog = ModelCatalog.shared

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?

    @State private var customLLMInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                whisperSection
                Divider()
                llmSection
            }
            .padding(20)
        }
        .onAppear { catalog.refreshStatus() }
    }

    // MARK: - Whisper

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("model.speech_recognition"), systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Picker("Engine", selection: $settings.speechEngine) {
                    ForEach(SpeechEngineType.allCases, id: \.self) { Text($0.label) }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if settings.speechEngine == .whisper {
                modelList(catalog.whisperModels, activeID: settings.whisperModel, type: .whisper)
            }
        }
    }

    // MARK: - LLM

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("model.text_formatting"), systemImage: "brain")
                .font(.headline)

            modelList(catalog.llmModels, activeID: settings.llmModel, type: .llm)

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
