import Foundation

struct InputRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rawText: String
    let processedText: String
    let rawCharCount: Int
    let processedCharCount: Int
    let wasProcessed: Bool
    let context: InputContext?

    init(rawText: String, processedText: String, wasProcessed: Bool, context: InputContext? = nil) {
        self.init(
            id: UUID(),
            date: Date(),
            rawText: rawText,
            processedText: processedText,
            wasProcessed: wasProcessed,
            context: context
        )
    }

    init(id: UUID, date: Date, rawText: String, processedText: String, wasProcessed: Bool, context: InputContext? = nil) {
        self.id = id
        self.date = date
        self.rawText = rawText
        self.processedText = processedText
        self.rawCharCount = rawText.count
        self.processedCharCount = processedText.count
        self.wasProcessed = wasProcessed
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case id, date, rawText, processedText, rawCharCount, processedCharCount, wasProcessed, context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        rawText = try container.decode(String.self, forKey: .rawText)
        processedText = try container.decode(String.self, forKey: .processedText)
        rawCharCount = try container.decodeIfPresent(Int.self, forKey: .rawCharCount) ?? rawText.count
        processedCharCount = try container.decodeIfPresent(Int.self, forKey: .processedCharCount) ?? processedText.count
        wasProcessed = try container.decode(Bool.self, forKey: .wasProcessed)
        context = try container.decodeIfPresent(InputContext.self, forKey: .context)
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }

        return [
            rawText,
            processedText,
            context?.appName,
            context?.bundleIdentifier,
            context?.windowTitle,
            context?.screenContext,
        ].contains { value in
            value?.lowercased().contains(normalized) == true
        }
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
        pruneExpired()
    }

    func addRecord(rawText: String, processedText: String, wasProcessed: Bool, context: InputContext? = nil) {
        let record = InputRecord(rawText: rawText, processedText: processedText, wasProcessed: wasProcessed, context: context)
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        pruneExpired()
        save()
    }

    func replaceLatestRecord(rawText: String, processedText: String, wasProcessed: Bool, context: InputContext? = nil) {
        guard let latest = records.first, latest.rawText == rawText else {
            addRecord(rawText: rawText, processedText: processedText, wasProcessed: wasProcessed, context: context)
            return
        }

        records[0] = InputRecord(
            id: latest.id,
            date: latest.date,
            rawText: rawText,
            processedText: processedText,
            wasProcessed: wasProcessed,
            context: context ?? latest.context
        )
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

    private func pruneExpired() {
        guard let interval = AppSettings.shared.historyRetention.timeInterval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let before = records.count
        records.removeAll { $0.date < cutoff }
        if records.count < before { save() }
    }
}
