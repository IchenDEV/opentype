import Foundation

extension PromptCatalog {
    static func activePersonalDictionarySection(_ entries: String, inputLanguage: InputLanguage) -> String? {
        let entries = entries.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            个人词库：
            \(entries)
            """
        case .english:
            return """
            Personal dictionary:
            \(entries)
            """
        case .japanese:
            return """
            個人辞書：
            \(entries)
            """
        case .korean:
            return """
            개인 사전:
            \(entries)
            """
        }
    }

    static func activeEditRulesSection(_ rules: String, inputLanguage: InputLanguage) -> String? {
        let rules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rules.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            额外编辑规则：
            \(rules)
            """
        case .english:
            return """
            Extra edit rules:
            \(rules)
            """
        case .japanese:
            return """
            追加編集ルール：
            \(rules)
            """
        case .korean:
            return """
            추가 편집 규칙:
            \(rules)
            """
        }
    }
}
