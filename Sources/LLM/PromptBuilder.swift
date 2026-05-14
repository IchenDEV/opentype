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

        var parts: [String]

        if settings.useCustomSystemPrompt, !settings.customSystemPrompt.isEmpty {
            parts = [settings.customSystemPrompt]
        } else {
            let basePrompt = baseSystemPrompt(inputLanguage: inputLanguage)
            parts = [basePrompt]

            if style.usesCustomPrompt {
                if !stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(inputLanguage == .chinese ? "自定义风格：\(stylePrompt)" : "Custom style: \(stylePrompt)")
                }
            } else {
                parts.append(stylePromptSection(style: style, inputLanguage: inputLanguage))
                let fewShots = styleFewShotSection(style: style, inputLanguage: inputLanguage)
                if !fewShots.isEmpty {
                    parts.append(fewShots)
                }
            }
        }

        if !screenContext.isEmpty {
            parts.append(inputLanguage == .chinese
                ? """
                屏幕文字，仅供纠错和专有名词参考，不要混入输出：
                ---
                \(screenContext)
                ---
                """
                : """
                On-screen text for correction and proper nouns only. Do not copy into output:
                ---
                \(screenContext)
                ---
                """)
        }

        if !memoryContext.isEmpty {
            parts.append(inputLanguage == .chinese
                ? """
                最近输入，仅供语境和专有名词参考：
                ---
                \(memoryContext)
                ---
                """
                : """
                Recent input for context and proper nouns only:
                ---
                \(memoryContext)
                ---
                """)
        }

        return parts.joined(separator: "\n\n")
    }

    static func buildUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return "以下是语音识别原文。请先在内部判断错别字、同音词、误识别词、漏字、多字和专有名词，再直接输出整理后的最终文本：\n<<<\n\(text)\n>>>"
        case .english, .japanese, .korean:
            return "Raw ASR transcript. Internally check typos, homophones, ASR substitutions, missing words, extra words, and proper nouns, then output only the final rewritten text:\n<<<\n\(text)\n>>>"
        }
    }

    static func buildCommandSystemPrompt(screenContext: String, memoryContext: String = "", inputLanguage: InputLanguage = .chinese) -> String {
        let base: String
        if inputLanguage == .chinese {
            base = """
            你是一个语音助手。用户通过语音下达指令，你需要根据指令生成回复文本。
            直接输出回复内容，不要使用思维标签，不要解释你的推理过程。

            规则：
            1. 根据用户指令和屏幕上下文，生成合适的回复文本
            2. 回复应该简洁、自然、得体
            3. 如果用户说"回复"或"帮我回复"，生成适合作为回复的文本
            4. 如果用户说"总结"或"概括"，对屏幕内容进行总结
            5. 如果用户要求翻译，进行翻译
            6. 输出纯文本，不要添加多余的标记
            """
        } else {
            base = """
            You are a voice assistant. The user gives voice commands, and you generate response text.
            Output the response directly without thinking tags or explanations.

            Rules:
            1. Generate appropriate response text based on the user's command and screen context
            2. Responses should be concise, natural, and appropriate
            3. If the user says "reply" or "respond", generate text suitable as a reply
            4. If the user says "summarize", summarize the screen content
            5. If the user asks to translate, perform the translation
            6. Output plain text without extra markup
            """
        }

        var parts = [base]
        if !screenContext.isEmpty {
            let screenLabel = inputLanguage == .chinese
                ? "以下是用户当前屏幕上的文字内容："
                : "Screen content below:"
            parts.append("""
            \(screenLabel)
            ---
            \(screenContext)
            ---
            """)
        }
        if !memoryContext.isEmpty {
            parts.append(inputLanguage == .chinese
                ? """
                以下是用户最近的输入历史，可作为上下文参考：
                ---
                \(memoryContext)
                ---
                """
                : """
                Recent input history for context:
                ---
                \(memoryContext)
                ---
                """)
        }
        return parts.joined(separator: "\n\n")
    }
}
