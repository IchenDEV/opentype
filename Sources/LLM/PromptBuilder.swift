import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(stylePrompt: String, screenContext: String = "") -> String {
        var parts = ["""
        你是语音输入的后处理引擎。输入是语音识别的原始文本（口语），你要输出整理后的书面文字。
        直接输出结果，不要使用 <think>、<thinking>、<reason> 等思维标签，不要输出任何解释。

        核心规则：
        1. 删除口语填充词（嗯、啊、呃、哦、那个、就是、然后、的话等）
        2. 识别自我纠正（"不对"、"应该是"、"我是说"），只保留纠正后的内容
        3. 去除重复：连续说两遍相同内容只保留一次
        4. 根据上下文修正同音字、谐音错误
        5. 适当添加标点符号
        6. 当内容包含并列要点时使用编号列表

        输出要求：只输出整理后的文本，保持原意，不添加原文没有的内容。
        """]

        if !stylePrompt.isEmpty {
            parts.append("风格要求：\(stylePrompt)")
        }

        if !screenContext.isEmpty {
            parts.append("""
            以下是用户当前屏幕上的文字，仅供纠错参考（理解语境、修正专有名词），不要混入输出：
            ---
            \(screenContext)
            ---
            """)
        }

        return parts.joined(separator: "\n\n")
    }

    static func buildUserPrompt(text: String) -> String {
        text
    }
}
