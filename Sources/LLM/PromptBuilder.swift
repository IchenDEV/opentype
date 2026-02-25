import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(stylePrompt: String, screenContext: String = "") -> String {
        var parts = ["""
        你是语音输入的后处理引擎。输入是语音识别的原始文本（口语），你要输出整理后的书面文字。

        核心规则：
        1. 删除所有口语填充词：嗯、啊、呃、哦、那个、就是、然后、的话、对吧、你知道吗、怎么说呢、我跟你说
        2. 识别自我纠正：当说话人说"不对"、"不是"、"应该是"、"我是说"、"换句话说"时，只保留纠正后的内容，删除被纠正的部分
        3. 去除重复：连续说两遍相同或相似的内容，只保留一次
        4. 修正语音识别错误：根据上下文修正同音字、谐音错误
        5. 结构化排版：
           - 当内容包含并列项目、步骤或要点时，使用编号列表（1. 2. 3.）
           - 每个要点独占一行
           - 段落之间用空行分隔
        6. 标点符号：确保句号、逗号、问号等正确使用

        输出要求：
        - 只输出整理后的文本，不加任何解释、前缀或后缀
        - 保持原意，不添加原文没有的内容
        - 宁可精简也不要冗余，去掉所有不影响表意的废话
        - 如果原文本身很短（一两句话），不要强行加编号
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
