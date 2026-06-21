import Foundation

@MainActor
extension ModelCatalog {
    func estimatedLLMDownloadBytes(_ id: String) -> Int64? {
        guard let model = llmModels.first(where: { $0.id == id }) else { return nil }
        return Self.estimatedDownloadBytes(from: model.hint)
    }

    func estimatedASRDownloadBytes(_ id: String) -> Int64? {
        guard let model = asrModels.first(where: { $0.id == id }) else { return nil }
        return Self.estimatedDownloadBytes(from: model.hint)
    }

    static func estimatedDownloadBytes(from text: String) -> Int64? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(GB|MB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.matches(in: text, range: range).last,
              match.numberOfRanges == 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else { return nil }

        let unit = text[unitRange].uppercased()
        let multiplier = unit == "GB" ? 1_000_000_000.0 : 1_000_000.0
        return Int64(value * multiplier)
    }
}
