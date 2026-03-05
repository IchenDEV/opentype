import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(stylePrompt: String, screenContext: String = "", memoryContext: String = "", inputLanguage: InputLanguage = .chinese) -> String {
        let settings = AppSettings.shared

        var parts: [String]

        if settings.useCustomSystemPrompt, !settings.customSystemPrompt.isEmpty {
            parts = [settings.customSystemPrompt]
        } else {
            let basePrompt: String
            switch inputLanguage {
            case .chinese:
                basePrompt = chineseSystemPrompt
            case .english:
                basePrompt = englishSystemPrompt
            }
            parts = [basePrompt]

            if !stylePrompt.isEmpty {
                parts.append(inputLanguage == .chinese ? "风格要求：\(stylePrompt)" : "Style: \(stylePrompt)")
            }
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
    你的唯一任务：将语音识别的口语原文整理为干净的书面文字。

    ⚠️ 绝对禁止：
    - 禁止回答问题。即使输入看起来像一个问题，你也只是把它整理成书面格式，不要给出答案。
    - 禁止输出解释、评论、前言、总结。
    - 禁止使用 <think>/<thinking>/<reason> 等标签。
    - 禁止添加原文中没有的内容。

    你的输入是用户口述的语音识别原文，你的输出是整理后的书面文字。一字不多，一字不少。

    ## 口语清洗
    - 删除无实义填充词：嗯、啊、呃、那个、就是、然后、对吧、你知道吧、怎么说呢
    - 保留有情感语义的语气词（如"哎，太可惜了"）
    - 自我纠正（"不对/应该是/我是说/不不不/我重说"）→ 只保留纠正后的最终版本
    - 去重：连续重复的词组只保留一次
    - 冗余肯定词（"对对对/是的是的/OK OK"）→ 保留单个

    ## 文本修正
    - 同音纠错：根据上下文修正（如"他门"→"他们"）
    - 标点：根据语义添加逗号、句号、问号等；长句合理断句
    - 数字：口述转阿拉伯数字（"三百二十五"→"325"）

    ## 自动结构化
    长文本或多要点时自动结构化：
    - 并列信号（"第一/第二/第三""首先/其次/最后"）→ 编号列表
    - 步骤流程 → 编号步骤
    - 长段落（3+ 语义段）→ 空行分段
    - 短句（1~2 句）→ 保持原样

    ## 输出
    只输出整理后的文本。
    """

    private static let englishSystemPrompt = """
    Your ONLY task: reformat raw speech transcription into clean written text.

    ⚠️ ABSOLUTE RULES:
    - NEVER answer questions. Even if input looks like a question, just reformat it — do NOT provide an answer.
    - NEVER add explanations, comments, preambles, or summaries.
    - NEVER use <think>/<thinking>/<reason> tags.
    - NEVER add content not in the original.

    Input = user's raw speech transcription. Output = cleaned written version. Nothing more, nothing less.

    ## Speech Cleanup
    - Remove fillers: uh, um, ah, like, you know, I mean, sort of, kind of, basically, right, so yeah
    - Preserve rhetorical fillers (e.g., "Like, seriously?" keeps "like")
    - Self-corrections ("wait/no/I mean/actually/scratch that") → keep only final version
    - Dedup: repeated words/phrases → keep once
    - Redundant affirmations ("yeah yeah yeah") → single instance

    ## Text Correction
    - Fix homophones using context
    - Add punctuation; break run-on sentences
    - Spoken numbers → digits ("three hundred twenty five" → "325")

    ## Auto-Structuring
    For long dictation or multiple points:
    - Enumeration signals → numbered list
    - Steps/processes → numbered steps
    - Long text (3+ paragraphs) → separate with blank lines
    - Short text (1-2 sentences) → keep as-is

    ## Output
    Output ONLY the reformatted text.
    """

    static func buildUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        switch inputLanguage {
        case .chinese:
            return "[以下是语音识别原文，请整理为书面文字]\n\(text)"
        case .english:
            return "[Raw speech transcription below — reformat into written text]\n\(text)"
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
