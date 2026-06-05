import Foundation

enum PromptStylePrompts {
    static func customStyleSection(stylePrompt: String, inputLanguage: InputLanguage) -> String? {
        guard !stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return inputLanguage == .chinese
            ? "自定义风格：\(stylePrompt)"
            : "Custom style: \(stylePrompt)"
    }

    static func section(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
        switch (inputLanguage, style) {
        case (.auto, .casual), (.chinese, .casual), (.cantonese, .casual):
            return "风格：自然、直接。保留口语感，但仍要主动修正明显错别字、同音词、断句和语序小问题；不要把明显识别错误原样留下，也不要过度书面化。"
        case (.auto, .professional), (.chinese, .professional), (.cantonese, .professional):
            return "风格：专业整理。先做纠错，再整理表达。对明显同音错字、近音错字、漏字、多字、专有名词大小写和中英混排要更主动；把口语碎片改成完整、自然的书面句子。语义完整、结构清楚；只有原文明显是步骤、清单或待办时，才输出 1. 2. 3.。"
        case (.auto, .custom), (.chinese, .custom), (.cantonese, .custom):
            return ""
        case (.english, .professional), (.japanese, .professional), (.korean, .professional):
            return "Style: professional cleanup. Correct first, then rewrite. Be more active with obvious homophones, ASR substitutions, missing words, extra words, proper nouns, capitalization, and mixed-language terms. Turn spoken fragments into complete natural written sentences. Keep the meaning complete and the structure crisp. Use 1. 2. 3. only when the raw text is clearly a list, steps, or action items."
        case (.english, .casual), (.japanese, .casual), (.korean, .casual):
            return "Style: natural and direct. Keep an easy spoken tone, but still actively fix obvious typos, homophones, sentence breaks, and small wording mistakes. Do not leave clear ASR errors in place."
        case (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }

    static func fewShotSection(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
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

            专业整理强纠错示例：
            原文：把 open type 的 hot key 文案改一下不要影响菜单蓝
            输出：把 OpenType 的 hotkey 文案改一下，不要影响菜单栏。

            原文：这次发版先看登录留成有没有问题再看数据库前一有没有慢查询
            输出：这次发版先看登录流程有没有问题，再看数据库迁移有没有慢查询。
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

            Strong correction examples:
            Raw: update the open type hot key copy and do not affect the menu bore
            Output: Update the OpenType hotkey copy, and do not affect the menu bar.

            Raw: check the log in floor before release and then check whether the database migration has slow queries
            Output: Check the login flow before release, then check whether the database migration has slow queries.
            """
        case (.auto, .casual), (.chinese, .casual), (.cantonese, .casual),
             (.auto, .custom), (.chinese, .custom), (.cantonese, .custom),
             (.english, .casual), (.japanese, .casual), (.korean, .casual),
             (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }
}
