import Foundation

enum SelectionRewriteIntent: Equatable {
    case formal
    case casual
    case expand
    case title
    case keyPoints
    case decisions
    case questions
    case risks
    case deadlines
    case owners
    case meetingNotes
    case reply
    case replyBrief
    case replyFormal
    case replyFriendly
    case replyInEnglish
    case replyInChinese
    case replyAccept
    case replyDecline
    case replyClarify
    case summary
    case concise
    case proofread
    case table
    case bulletList
    case numberedList
    case actionItems
    case checklist
    case translateToEnglish
    case translateToChinese
    case custom(String)
}

enum SpokenEditCommand: Equatable {
    case replaceLast(String)
    case replaceSelection(String)
    case rewriteLast(SelectionRewriteIntent)
    case rewriteSelection(SelectionRewriteIntent)
    case deleteSelection
    case undoLastInsertion
}

enum SpokenEditCommandPayloadCleaner {
    static func cleanReplacement(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
