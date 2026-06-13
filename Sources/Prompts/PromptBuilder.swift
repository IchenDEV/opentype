import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(
        style: LanguageStyle,
        stylePrompt: String,
        screenContext: String = "",
        memoryContext: String = "",
        inputLanguage: InputLanguage = .chinese
    ) -> String {
        let settings = AppSettings.shared
        var parts = promptParts(
            settings: settings,
            style: style,
            stylePrompt: stylePrompt,
            inputLanguage: inputLanguage
        )
        parts.append(contentsOf: PromptCatalog.processingContextSections(
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: inputLanguage
        ))

        return parts.joined(separator: "\n\n")
    }

    static func buildUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        PromptCatalog.userPrompt(text: text, inputLanguage: inputLanguage)
    }

    static func buildCommandSystemPrompt(screenContext: String, memoryContext: String = "", inputLanguage: InputLanguage = .chinese) -> String {
        var parts = [PromptCatalog.commandSystemPrompt(inputLanguage: inputLanguage)]
        parts.append(contentsOf: PromptCatalog.commandContextSections(
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: inputLanguage
        ))
        return parts.joined(separator: "\n\n")
    }
}

private extension PromptBuilder {
    static func promptParts(
        settings: AppSettings,
        style: LanguageStyle,
        stylePrompt: String,
        inputLanguage: InputLanguage
    ) -> [String] {
        if settings.useCustomSystemPrompt, !settings.customSystemPrompt.isEmpty {
            return [settings.customSystemPrompt]
        }

        var parts = [PromptCatalog.baseSystemPrompt(inputLanguage: inputLanguage)]
        if style.usesCustomPrompt {
            if let customStyle = PromptStylePrompts.customStyleSection(
                stylePrompt: stylePrompt,
                inputLanguage: inputLanguage
            ) {
                parts.append(customStyle)
            }
            return parts
        }

        parts.append(PromptStylePrompts.section(style: style, inputLanguage: inputLanguage))
        let fewShots = PromptStylePrompts.fewShotSection(style: style, inputLanguage: inputLanguage)
        if !fewShots.isEmpty {
            parts.append(fewShots)
        }
        return parts
    }
}
