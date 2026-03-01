import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(stylePrompt: String, screenContext: String = "", memoryContext: String = "", inputLanguage: InputLanguage = .chinese) -> String {
        let basePrompt: String
        switch inputLanguage {
        case .chinese:
            basePrompt = chineseSystemPrompt
        case .english:
            basePrompt = englishSystemPrompt
        }

        var parts = [basePrompt]

        if !stylePrompt.isEmpty {
            parts.append(inputLanguage == .chinese ? "风格要求：\(stylePrompt)" : "Style: \(stylePrompt)")
        }

        if !screenContext.isEmpty {
            parts.append(inputLanguage == .chinese
                ? """
                以下是用户当前屏幕上的文字，仅供纠错参考（理解语境、修正专有名词），不要混入输出：
                ---
                \(screenContext)
                ---
                """
                : """
                Below is on-screen text for context only (homophone correction, proper nouns). Do not mix into output:
                ---
                \(screenContext)
                ---
                """)
        }

        if !memoryContext.isEmpty {
            parts.append(inputLanguage == .chinese
                ? """
                以下是用户最近的输入历史，可作为上下文参考（理解语境、纠正专有名词）：
                ---
                \(memoryContext)
                ---
                """
                : """
                Recent input history for context (understanding context, correcting proper nouns):
                ---
                \(memoryContext)
                ---
                """)
        }

        return parts.joined(separator: "\n\n")
    }

    private static let chineseSystemPrompt = """
    你是语音输入的后处理引擎。输入是语音识别的原始文本（口语），你要输出整理后的书面文字。
    直接输出结果，不要使用 <think>、<thinking>、<reason> 等思维标签，不要输出任何解释。

    核心规则：
    1. 根据语境判断并清理无意义的口语填充词和语气词，但保留用户有意使用的语气表达
    2. 识别自我纠正（如"不对"、"应该是"、"我是说"），只保留纠正后的内容
    3. 去除重复：连续说两遍相同内容只保留一次
    4. 根据上下文修正同音字、谐音错误
    5. 适当添加标点符号
    6. 如果风格要求中指定了结构化输出，严格遵循其格式要求

    输出要求：只输出整理后的文本，保持原意，不添加原文没有的内容。
    """

    private static let englishSystemPrompt = """
    You are a post-processing engine for voice input. Input is transcribed speech (spoken). You must output clean written text.
    Output only the result. Do NOT use <think>, <thinking>, <reason> or any thinking tags. No explanations.

    Core rules:
    1. Clean up filler words and verbal hesitations based on context, but preserve intentional expressions
    2. Self-corrections: "I mean", "actually", "wait" — keep only the corrected content
    3. Deduplicate: if same content said twice consecutively, keep once
    4. Fix homophones and typos from speech recognition using context
    5. Add appropriate punctuation
    6. If the style instructions specify structured output, follow the format strictly

    Output: only the cleaned text. Preserve meaning. Do not add content not in the original.
    """

    static func buildUserPrompt(text: String) -> String {
        text
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
