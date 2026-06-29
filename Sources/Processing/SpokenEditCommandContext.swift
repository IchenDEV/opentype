import Foundation

extension SpokenEditCommandResolutionContext {
    static let previewCharacterLimit = 320

    static func preview(_ text: String?) -> String? {
        preview(text, limit: previewCharacterLimit)
    }

    static func preview(_ text: String?, limit: Int) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }

        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
