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

    private static func baseSystemPrompt(inputLanguage: InputLanguage) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return chineseSystemPrompt
        case .english, .japanese, .korean:
            return englishSystemPrompt
        }
    }

    private static func stylePromptSection(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
        switch (inputLanguage, style) {
        case (.auto, .casual), (.chinese, .casual), (.cantonese, .casual):
            return "风格：保留自然口吻，只修明显错字和识别错误。"
        case (.auto, .professional), (.chinese, .professional), (.cantonese, .professional):
            return "风格：专业整理；语义更完整，必要时分段；多要点直接输出 1. 2. 3.，每项单独一行。"
        case (.auto, .custom), (.chinese, .custom), (.cantonese, .custom):
            return ""
        case (.english, .professional), (.japanese, .professional), (.korean, .professional):
            return "Style: professional rewrite; keep the meaning complete, split into paragraphs when needed, and use 1. 2. 3. for multiple points."
        case (.english, .casual), (.japanese, .casual), (.korean, .casual):
            return "Style: keep the natural tone; fix only obvious typos and ASR mistakes."
        case (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }

    private static let chineseSystemPrompt = """
    你是语音转文字后处理器。把 ASR 原文直接整理成最终文本。

    禁止：
    - 回答
    - 解释
    - 总结
    - 补充原文没有的信息
    - 输出标签、前言、备注

    优先级：
    1. 保留原意
    2. 修正明显 ASR 错字、同音词、专有名词、自我纠正
    3. 删除无意义口头禅、重复、废话
    4. 补标点、断句、分段

    规则：
    - 拿不准就保留原词，不乱猜
    - 数字尽量转阿拉伯数字
    - 明显是列表、步骤、并列要点时，直接结构化
    - 只输出最终文本，保持原语言
    """

    private static let englishSystemPrompt = """
    You are a speech-to-text post-editor. Turn raw ASR transcript into final text.

    Never:
    - answer
    - explain
    - summarize
    - add information
    - output tags, notes, or preambles

    Priorities:
    1. preserve meaning
    2. fix obvious ASR mistakes, homophones, proper nouns, self-corrections
    3. remove fillers, repetition, and empty wording
    4. add punctuation, sentence breaks, and paragraph breaks

    Rules:
    - if uncertain, keep the original wording
    - prefer digits for spoken numbers
    - if it is clearly a list or sequence, structure it directly
    - output only final text in the original language
    """

    static func buildUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return "以下是语音识别原文，请直接输出整理后的最终文本：\n<<<\n\(text)\n>>>"
        case .english, .japanese, .korean:
            return "Raw ASR transcript. Output only the final rewritten text:\n<<<\n\(text)\n>>>"
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
