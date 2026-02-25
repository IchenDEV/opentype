import Foundation

struct InputRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rawText: String
    let processedText: String
    let rawCharCount: Int
    let processedCharCount: Int
    let wasProcessed: Bool

    init(rawText: String, processedText: String, wasProcessed: Bool) {
        self.id = UUID()
        self.date = Date()
        self.rawText = rawText
        self.processedText = processedText
        self.rawCharCount = rawText.count
        self.processedCharCount = processedText.count
        self.wasProcessed = wasProcessed
    }
}

struct InputStats {
    let totalInputs: Int
    let totalRawChars: Int
    let totalProcessedChars: Int
    let charsSaved: Int
    let todayInputs: Int
    let todayChars: Int
    let streakDays: Int

    var efficiencyRatio: Double {
        guard totalRawChars > 0 else { return 0 }
        return Double(charsSaved) / Double(totalRawChars)
    }
}

@MainActor
final class InputHistory: ObservableObject {
    static let shared = InputHistory()

    @Published private(set) var records: [InputRecord] = []

    private let fileURL: URL
    private static let maxRecords = 500

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("input_history.json")
        load()
    }

    func addRecord(rawText: String, processedText: String, wasProcessed: Bool) {
        let record = InputRecord(rawText: rawText, processedText: processedText, wasProcessed: wasProcessed)
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        save()
    }

    func deleteRecord(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    var stats: InputStats {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        let todayRecords = records.filter { $0.date >= todayStart }
        let totalRaw = records.reduce(0) { $0 + $1.rawCharCount }
        let totalProcessed = records.reduce(0) { $0 + $1.processedCharCount }

        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var checkDate = todayStart
        while uniqueDays.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return InputStats(
            totalInputs: records.count,
            totalRawChars: totalRaw,
            totalProcessedChars: totalProcessed,
            charsSaved: max(0, totalRaw - totalProcessed),
            todayInputs: todayRecords.count,
            todayChars: todayRecords.reduce(0) { $0 + $1.processedCharCount },
            streakDays: streak
        )
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([InputRecord].self, from: data) {
            records = decoded
        }
    }
}
