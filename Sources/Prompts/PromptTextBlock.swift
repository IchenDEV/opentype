enum PromptTextBlock {
    static func block(_ text: String) -> String {
        """
        <<<
        \(safe(text))
        >>>
        """
    }

    static func safe(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<<<", with: "< < <")
            .replacingOccurrences(of: ">>>", with: "> > >")
    }
}
