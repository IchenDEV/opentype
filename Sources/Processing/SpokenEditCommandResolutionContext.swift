enum SpokenEditCommandTargetAvailability {
    case available
    case unavailable
    case unknown

    var chinesePromptDescription: String {
        switch self {
        case .available: return "可用"
        case .unavailable: return "不可用"
        case .unknown: return "未知"
        }
    }

    var englishPromptDescription: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        }
    }

    var japanesePromptDescription: String {
        switch self {
        case .available: return "利用可能"
        case .unavailable: return "利用不可"
        case .unknown: return "不明"
        }
    }

    var koreanPromptDescription: String {
        switch self {
        case .available: return "사용 가능"
        case .unavailable: return "사용 불가"
        case .unknown: return "알 수 없음"
        }
    }
}

struct SpokenEditCommandResolutionContext {
    var lastInsertion: SpokenEditCommandTargetAvailability = .unknown
    var selectedText: SpokenEditCommandTargetAvailability = .unknown
    var lastInsertionPreview: String?
    var selectedTextPreview: String?

    static let unknown = SpokenEditCommandResolutionContext()
}

enum SpokenEditCommandLLMResolution: Equatable {
    case command(SpokenEditCommand)
    case none
}
