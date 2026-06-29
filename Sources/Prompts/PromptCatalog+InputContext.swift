extension PromptCatalog {
    static func inputTargetContextSection(_ context: InputContext?, inputLanguage: InputLanguage) -> String? {
        guard let context else { return nil }
        let details = inputTargetDetails(context, inputLanguage: inputLanguage)
        guard !details.isEmpty else { return nil }

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            当前输入目标，仅用于判断语气、专有名词和应用场景，不要把这些元信息写入输出：
            \(details)
            """
        case .english:
            return """
            Current input target for tone, proper nouns, and app context only. Do not copy this metadata into the output:
            \(details)
            """
        case .japanese:
            return """
            現在の入力先。語調、固有名詞、アプリ文脈の判断にだけ使い、このメタ情報を出力に書かないでください：
            \(details)
            """
        case .korean:
            return """
            현재 입력 대상입니다. 어조, 고유명사, 앱 맥락 판단에만 사용하고 이 메타정보를 출력에 쓰지 마세요:
            \(details)
            """
        }
    }
}

private func inputTargetDetails(_ context: InputContext, inputLanguage: InputLanguage) -> String {
    let labels: [(String, String?)]
    switch inputLanguage {
    case .auto, .chinese, .cantonese:
        labels = [
            ("应用", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("窗口", context.windowTitle),
        ]
    case .english:
        labels = [
            ("App", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("Window", context.windowTitle),
        ]
    case .japanese:
        labels = [
            ("アプリ", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("ウィンドウ", context.windowTitle),
        ]
    case .korean:
        labels = [
            ("앱", context.appName),
            ("Bundle", context.bundleIdentifier),
            ("창", context.windowTitle),
        ]
    }

    return labels
        .compactMap { label, value in
            guard let value else { return nil }
            return "- \(label): \(value)"
        }
        .joined(separator: "\n")
}
