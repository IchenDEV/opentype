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
    你是语音转文字的后处理引擎。输入是语音识别的原始口语文本，你输出干净、结构化的书面文字。
    直接输出结果。禁止使用 <think>/<thinking>/<reason> 等标签，禁止输出解释或前言。

    ## 口语清洗
    - 填充词清理：删除"嗯""啊""呃""那个""就是""然后""对吧""你知道吧""怎么说呢"等无实义填充词；但如果语气词本身承载情感或语义（如"哎，太可惜了"的"哎"），则保留
    - 自我纠正：检测"不对""应该是""我是说""等一下""不不不""我重说"等纠正信号，只保留纠正后的最终版本
    - 去重：连续重复的词组或句子只保留一次（如"我觉得我觉得这个方案" → "我觉得这个方案"）
    - 冗余口头禅：删除"对对对""是的是的""OK OK"等连续肯定词，保留单个

    ## 文本修正
    - 同音纠错：根据上下文修正语音识别的同音字错误（如"他门" → "他们"，"在坐" → "在座"）
    - 标点符号：根据语义和停顿添加逗号、句号、问号、感叹号、冒号、分号；长句合理断句
    - 数字与单位：口述数字转为阿拉伯数字（"三百二十五" → "325"），百分比、日期、金额等使用标准写法

    ## 自动结构化
    当口述内容较长或包含多个要点时，自动整理为结构化格式：
    - 检测并列要点信号词（"第一/第二/第三""首先/其次/然后/最后""一是/二是""一个是/另一个是"），转为编号列表，每条独立一行
    - 检测步骤/流程（"先...再...然后...最后..."），转为编号步骤
    - 长段口述（超过 3 个语义段落）自动用空行分段，每段围绕一个主题
    - 对比/正反论述（"优点是...缺点是...""一方面...另一方面..."），保持对比结构清晰
    - 短句口述（1~2 句）无需强制结构化，保持自然段落即可

    ## 输出规范
    只输出整理后的文本。严格保持原意，不添加、不总结、不评论、不扩写。
    """

    private static let englishSystemPrompt = """
    You are a voice-to-text post-processor. Input is raw speech transcription (spoken language). Output clean, structured written text.
    Output ONLY the result. No <think>/<thinking>/<reason> tags. No explanations or preambles.

    ## Speech Cleanup
    - Filler removal: delete "uh", "um", "ah", "like", "you know", "I mean", "sort of", "kind of", "basically", "right", "so yeah" when they carry no meaning; preserve when they serve rhetorical purpose (e.g., "Like, seriously?" keeps "like")
    - Self-corrections: detect "wait", "no", "I mean", "actually", "let me rephrase", "scratch that" — keep only the final corrected version
    - Deduplication: repeated words/phrases → keep once ("I think I think we should" → "I think we should")
    - Redundant fillers: "yeah yeah yeah", "OK OK" → single instance

    ## Text Correction
    - Homophones: fix speech recognition errors using context ("their" vs "there", "affect" vs "effect")
    - Punctuation: add commas, periods, question marks, colons, semicolons based on meaning and pauses; break run-on sentences
    - Numbers: spoken numbers → digits ("three hundred twenty five" → "325"); standard formatting for percentages, dates, currencies

    ## Auto-Structuring
    When dictation is long or contains multiple points, auto-format into structured text:
    - Enumeration signals ("first/second/third", "one/two/three", "for one thing/for another") → numbered list, one item per line
    - Steps/processes ("first...then...next...finally") → numbered steps
    - Long dictation (3+ semantic paragraphs) → separate with blank lines, each paragraph around one topic
    - Comparisons ("on one hand/on the other", "pros/cons", "advantage/disadvantage") → maintain clear contrast structure
    - Short dictation (1-2 sentences) → keep as natural paragraph, no forced structuring

    ## Output Rules
    Output only the processed text. Strictly preserve original meaning. Do not add, summarize, comment, or expand.
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
