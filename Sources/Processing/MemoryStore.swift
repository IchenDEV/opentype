import Foundation

@MainActor
enum MemoryStore {
    static func recentContext(limit: Int = 5, windowMinutes: Int = 30) -> String {
        let history = InputHistory.shared
        let cutoff = Date().addingTimeInterval(-Double(windowMinutes) * 60)

        let recent = history.records
            .filter { $0.date >= cutoff }
            .prefix(limit)

        guard !recent.isEmpty else { return "" }

        let lines = recent.reversed().map { record in
            let text = record.wasProcessed ? record.processedText : record.rawText
            return "[\(formatTime(record.date))] \(text)"
        }

        return lines.joined(separator: "\n")
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
