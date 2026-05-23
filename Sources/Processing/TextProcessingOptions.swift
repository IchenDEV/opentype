import Foundation

struct TextProcessingOptions {
    var inputLanguage: InputLanguage
    var languageStyle: LanguageStyle
    var customStylePrompt: String
    var llmModel: String
    var useRemoteLLM: Bool
    var remoteBaseURL: String
    var remoteAPIKey: String
    var remoteModel: String
    var remoteProvider: RemoteProvider

    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        self.inputLanguage = inputLanguage ?? settings.inputLanguage
        self.languageStyle = settings.languageStyle
        self.customStylePrompt = settings.customStylePrompt
        self.llmModel = settings.llmModel
        self.useRemoteLLM = settings.useRemoteLLM
        self.remoteBaseURL = settings.remoteBaseURL
        self.remoteAPIKey = settings.remoteAPIKey
        self.remoteModel = settings.remoteModel
        self.remoteProvider = settings.remoteProvider
    }
}
