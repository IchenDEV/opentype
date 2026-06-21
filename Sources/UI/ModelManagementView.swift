import SwiftUI
import AppKit

struct ModelManagementView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @StateObject var catalog = ModelCatalog.shared

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    var onLoadLLM: (() -> Void)?
    var onUnloadLocalASR: (() -> Void)?

    @State var customLLMInput = ""
    @State var showImportError = false
    @State var importErrorMessage = ""
    @State var selectedModelFamily: ModelCatalog.ModelFamily? = .qwen
    @State var showLegacyModels = false
    let benchmarkEngine = LLMEngine()

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
}
