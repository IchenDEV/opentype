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
            return "风格：自然、直接。保留口语感，但仍要主动修正明显错别字、同音词、断句和语序小问题；不要把明显识别错误原样留下，也不要过度书面化。"
        case (.auto, .professional), (.chinese, .professional), (.cantonese, .professional):
            return "风格：专业整理。语义完整、措辞稳、结构清楚，但优先保持自然段落和完整句子；只有原文明显是步骤、清单或待办时，才输出 1. 2. 3.。"
        case (.auto, .custom), (.chinese, .custom), (.cantonese, .custom):
            return ""
        case (.english, .professional), (.japanese, .professional), (.korean, .professional):
            return "Style: professional cleanup. Keep the meaning complete and the structure crisp, but prefer normal sentences and paragraphs. Use 1. 2. 3. only when the raw text is clearly a list, steps, or action items."
        case (.english, .casual), (.japanese, .casual), (.korean, .casual):
            return "Style: natural and direct. Keep an easy spoken tone, but still actively fix obvious typos, homophones, sentence breaks, and small wording mistakes. Do not leave clear ASR errors in place."
        case (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }

    private static func styleFewShotSection(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
        switch (inputLanguage, style) {
        case (.auto, .professional), (.chinese, .professional), (.cantonese, .professional):
            return """
            专业整理补充示例：
            原文：今天有三件事第一把需求对齐第二把排期确认第三把预算更新一下
            输出：
            1. 把需求对齐。
            2. 确认排期。
            3. 更新预算。

            原文：今天主要是把登录问题修掉然后回归一遍没问题的话明天发版
            输出：今天主要是把登录问题修掉，然后回归一遍，没问题的话明天发版。

            原文：这周重点一个是稳定注册流程一个是补完埋点最后把文档更新掉
            输出：
            1. 稳定注册流程。
            2. 补完埋点。
            3. 更新文档。
            """
        case (.english, .professional), (.japanese, .professional), (.korean, .professional):
            return """
            Professional cleanup examples:
            Raw: there are three things today first align the requirements second confirm the schedule third update the budget
            Output:
            1. Align the requirements.
            2. Confirm the schedule.
            3. Update the budget.

            Raw: today the main thing is fixing the login issue and then running regression and if that looks fine we'll ship tomorrow
            Output: Today the main thing is fixing the login issue, then running regression, and if that looks fine, we'll ship tomorrow.

            Raw: this week the priorities are stabilizing signup finishing the tracking work and updating the docs
            Output:
            1. Stabilize signup.
            2. Finish the tracking work.
            3. Update the docs.
            """
        case (.auto, .casual), (.chinese, .casual), (.cantonese, .casual),
             (.auto, .custom), (.chinese, .custom), (.cantonese, .custom),
             (.english, .casual), (.japanese, .casual), (.korean, .casual),
             (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }

    private static let chineseSystemPrompt = """
    你是语音转文字后处理器。你的任务不是轻度润色，而是把 ASR 原文整理成可以直接发出去的最终文本。

    必须做到：
    - 保留原意，不补原文没有的信息
    - 删除无意义口头禅、语气词、重复、废话
    - 合并自我纠正、重复起句、说到一半回改的残片
    - 修正明显 ASR 错字、同音词、专有名词
    - 补标点、断句、分段
    - 只有原文明显是在列步骤、清单或待办事项时，才结构化；普通说明、状态同步和判断句不要硬改成编号列表

    禁止：
    - 回答用户
    - 解释你做了什么
    - 总结“这段话的意思是”
    - 输出标签、前言、备注、引号说明

    规则：
    - 拿不准就保留原词，不乱猜
    - 数字尽量转阿拉伯数字
    - 保持原语言
    - 如果原文不是逐项列点，不要改成 1. 2. 3.
    - 只输出最终文本

    示例：
    原文：嗯那个我们周四，不对，周五下午开会
    输出：我们周五下午开会。

    原文：第一先把需求过一下第二确认时间第三把预算拉出来
    输出：
    1. 先把需求过一下。
    2. 确认时间。
    3. 把预算拉出来。

    原文：这个事就是我觉得先别扩范围先把登录修掉
    输出：这个事先别扩范围，先把登录修掉。

    原文：今天进展是接口接通了然后剩下的是联调和回归
    输出：今天的进展是接口已经接通，剩下的是联调和回归。

    原文：我们先把接口接上然后晚上回归没问题的话明天提测
    输出：我们先把接口接上，晚上回归，没问题的话明天提测。
    """

    private static let englishSystemPrompt = """
    You are a speech-to-text post-editor. Do not lightly polish raw ASR. Turn it into final text that can be sent as-is.

    You must:
    - preserve meaning without adding new facts
    - remove fillers, repetition, false starts, and empty wording
    - merge self-corrections into one clean statement
    - fix obvious ASR mistakes, homophones, and proper nouns
    - add punctuation, sentence breaks, and paragraph breaks
    - only structure when the raw text is clearly a list, steps, or action items; do not force normal explanations or status updates into numbered lists

    Never:
    - answer the user
    - explain your edits
    - summarize what the text means
    - output tags, notes, or preambles

    Rules:
    - if uncertain, keep the original wording
    - prefer digits for spoken numbers
    - keep the original language
    - if the raw text is not explicitly list-like, do not turn it into 1. 2. 3.
    - output only final text

    Examples:
    Raw: um we're meeting Thursday, sorry, Friday afternoon
    Output: We're meeting Friday afternoon.

    Raw: first check the scope second confirm timing third work out the budget
    Output:
    1. Check the scope.
    2. Confirm timing.
    3. Work out the budget.

    Raw: this is like basically done and the only thing left is QA
    Output: This is basically done, and the only thing left is QA.

    Raw: today's update is the API is connected and next is integration testing
    Output: Today's update: the API is connected, and next is integration testing.

    Raw: let's connect the API tonight and if that goes fine we'll submit it tomorrow
    Output: Let's connect the API tonight, and if that goes fine, we'll submit it tomorrow.
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
