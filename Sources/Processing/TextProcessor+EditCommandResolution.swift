import Foundation

enum SpokenEditCommandTargetAvailability {
    case available
    case unavailable
    case unknown

    var chinesePromptDescription: String {
        switch self {
        case .available: return "可用"
        case .unavailable: return "不可用"
        case .unknown: return "未知"
        }
    }

    var englishPromptDescription: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        }
    }

    var japanesePromptDescription: String {
        switch self {
        case .available: return "利用可能"
        case .unavailable: return "利用不可"
        case .unknown: return "不明"
        }
    }

    var koreanPromptDescription: String {
        switch self {
        case .available: return "사용 가능"
        case .unavailable: return "사용 불가"
        case .unknown: return "알 수 없음"
        }
    }
}

struct SpokenEditCommandResolutionContext {
    var lastInsertion: SpokenEditCommandTargetAvailability = .unknown
    var selectedText: SpokenEditCommandTargetAvailability = .unknown
    var lastInsertionPreview: String?
    var selectedTextPreview: String?

    static let unknown = SpokenEditCommandResolutionContext()
}

enum SpokenEditCommandLLMResolution: Equatable {
    case command(SpokenEditCommand)
    case none
}

extension TextProcessor {
    func resolveSpokenEditCommand(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommand? {
        guard case .command(let command) = await resolveSpokenEditCommandResolution(
            text: text,
            options: options,
            context: context
        ) else {
            return nil
        }
        return command
    }

    func resolveSpokenEditCommandResolution(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommandLLMResolution? {
        let transcript = FormattingHeuristics.normalizeInput(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        do {
            let generationOptions = editCommandResolutionOptions(for: transcript)
            let result = try await generateText(
                prompt: PromptBuilder.buildEditCommandResolverUserPrompt(
                    text: transcript,
                    inputLanguage: options.inputLanguage,
                    context: context
                ),
                systemPrompt: systemPromptWithPersonalContext(
                    PromptBuilder.buildEditCommandResolverSystemPrompt(
                        inputLanguage: options.inputLanguage
                    ),
                    inputLanguage: options.inputLanguage
                ),
                options: options,
                maxTokens: generationOptions.maxTokens,
                temperature: generationOptions.temperature
            )
            let resolution = SpokenEditCommandLLMResolver.resolution(from: result)
            if case .command = resolution {
                Log.info("[TextProcessor] LLM resolved a spoken edit command")
            }
            return resolution
        } catch {
            Log.error("[TextProcessor] LLM edit command resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    func editCommandResolutionOptions(for text: String) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxTokens = characterCount > 160 ? 384 : 256
        return GenerationOptions(maxTokens: maxTokens, temperature: 0)
    }
}

enum SpokenEditCommandLLMResolver {
    static func resolution(from text: String) -> SpokenEditCommandLLMResolution? {
        var fallbackResolution: SpokenEditCommandLLMResolution?
        for data in jsonObjectDataCandidates(from: text) {
            guard let resolution = try? JSONDecoder().decode(Resolution.self, from: data),
                  resolution.hasAction else {
                continue
            }
            guard let resolved = resolvedAction(from: resolution) else { continue }
            if case .command = resolved {
                return resolved
            }
            fallbackResolution = resolved
        }
        return fallbackResolution
    }

    static func command(from text: String) -> SpokenEditCommand? {
        guard case .command(let command) = resolution(from: text) else {
            return nil
        }
        return command
    }
}

private extension SpokenEditCommandLLMResolver {
    struct Resolution: Decodable {
        let action: LLMTextValue?
        let intent: LLMTextValue?
        let replacement: LLMReplacementValue?
        let confidence: LLMNumericConfidence?
        let hasAction: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: LLMResolutionCodingKey.self)
            hasAction = container.caseInsensitiveKey("action") != nil
            action = try container.decodeIfPresentCaseInsensitive(LLMTextValue.self, forKey: "action")
            intent = try container.decodeIfPresentCaseInsensitive(LLMTextValue.self, forKey: "intent")
            replacement = try container.decodeIfPresentCaseInsensitive(LLMReplacementValue.self, forKey: "replacement")
            confidence = try container.decodeIfPresentCaseInsensitive(LLMNumericConfidence.self, forKey: "confidence")
        }
    }

    static func resolvedAction(from resolution: Resolution) -> SpokenEditCommandLLMResolution? {
        let action = normalizedIdentifier(resolution.action?.text)
        if action == "none" {
            return SpokenEditCommandLLMResolution.none
        }

        guard let confidence = resolution.confidence?.value else {
            return SpokenEditCommandLLMResolution.none
        }
        guard confidence >= minimumConfidence else {
            return SpokenEditCommandLLMResolution.none
        }

        switch action {
        case "replace_last", "replacelast":
            guard emptyPayload(resolution.intent?.text),
                  let command = replacementCommand(resolution.replacement?.text, command: SpokenEditCommand.replaceLast) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(command)
        case "replace_selection", "replaceselection":
            guard emptyPayload(resolution.intent?.text),
                  let command = replacementCommand(resolution.replacement?.text, command: SpokenEditCommand.replaceSelection) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(command)
        case "rewrite_last", "rewritelast":
            guard emptyPayload(resolution.replacement?.text),
                  let intent = SelectionRewriteIntent.llmValue(resolution.intent?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.rewriteLast(intent))
        case "rewrite_selection", "rewriteselection":
            guard emptyPayload(resolution.replacement?.text),
                  let intent = SelectionRewriteIntent.llmValue(resolution.intent?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.rewriteSelection(intent))
        case "delete_selection", "deleteselection":
            guard emptyPayload(resolution.intent?.text), emptyPayload(resolution.replacement?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.deleteSelection)
        case "undo_last_insertion", "undolastinsertion":
            guard emptyPayload(resolution.intent?.text), emptyPayload(resolution.replacement?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.undoLastInsertion)
        default:
            return SpokenEditCommandLLMResolution.none
        }
    }

    static let minimumConfidence = 0.75

    static func emptyPayload(_ rawValue: String?) -> Bool {
        normalizedIdentifier(rawValue).isEmpty || normalizedIdentifier(rawValue) == "null"
    }

    static func replacementCommand(
        _ rawReplacement: String?,
        command: (String) -> SpokenEditCommand
    ) -> SpokenEditCommand? {
        let replacement = SpokenEditCommandPayloadCleaner.cleanReplacement(rawReplacement ?? "")
        return replacement.isEmpty ? nil : command(replacement)
    }

    static func jsonObjectDataCandidates(from text: String) -> [Data] {
        LLMStructuredOutput.jsonObjectDataCandidates(from: text)
    }
}

extension SelectionRewriteIntent {
    static func llmValue(_ rawValue: String?) -> SelectionRewriteIntent? {
        let customInstruction = customInstructionValue(rawValue)
        guard !customInstruction.isEmpty else { return nil }
        if let preset = presetLLMValue(rawValue) {
            return preset
        }
        return .custom(customInstruction)
    }

    private static func presetLLMValue(_ rawValue: String?) -> SelectionRewriteIntent? {
        switch normalizedIdentifier(rawValue) {
        case "formal": return .formal
        case "casual": return .casual
        case "expand": return .expand
        case "title": return .title
        case "key_points", "keypoints": return .keyPoints
        case "decisions": return .decisions
        case "questions": return .questions
        case "risks": return .risks
        case "deadlines": return .deadlines
        case "owners": return .owners
        case "meeting_notes", "meetingnotes": return .meetingNotes
        case "reply": return .reply
        case "reply_brief", "replybrief": return .replyBrief
        case "reply_formal", "replyformal": return .replyFormal
        case "reply_friendly", "replyfriendly": return .replyFriendly
        case "reply_in_english", "replyinenglish": return .replyInEnglish
        case "reply_in_chinese", "replyinchinese": return .replyInChinese
        case "reply_accept", "replyaccept": return .replyAccept
        case "reply_decline", "replydecline": return .replyDecline
        case "reply_clarify", "replyclarify": return .replyClarify
        case "summary": return .summary
        case "concise": return .concise
        case "proofread": return .proofread
        case "table": return .table
        case "bullet_list", "bulletlist": return .bulletList
        case "numbered_list", "numberedlist": return .numberedList
        case "action_items", "actionitems": return .actionItems
        case "checklist": return .checklist
        case "translate_to_english", "translatetoenglish": return .translateToEnglish
        case "translate_to_chinese", "translatetochinese": return .translateToChinese
        default: return nil
        }
    }

    private static func customInstructionValue(_ rawValue: String?) -> String {
        let cleaned = (rawValue ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, normalizedIdentifier(cleaned) != "null" else { return "" }

        return String(cleaned.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func normalizedIdentifier(_ rawValue: String?) -> String {
    (rawValue ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}
