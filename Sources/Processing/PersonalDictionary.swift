import Foundation

struct DictionaryEntry: Codable, Identifiable {
    var id = UUID()
    var original: String
    var replacement: String
    var enabled: Bool = true
}

struct EditRule: Codable, Identifiable {
    var id = UUID()
    var description: String
    var enabled: Bool = true
}

final class PersonalDictionary: ObservableObject {
    static let shared = PersonalDictionary()

    @Published var entries: [DictionaryEntry] = []
    @Published var editRules: [EditRule] = []

    private let entriesURL: URL
    private let rulesURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        entriesURL = dir.appendingPathComponent("dictionary.json")
        rulesURL = dir.appendingPathComponent("edit_rules.json")
        load()
    }

    func applyReplacements(to text: String) -> String {
        var result = text
        for entry in entries where entry.enabled {
            result = result.replacingOccurrences(of: entry.original, with: entry.replacement)
        }
        return result
    }

    func activeRulesDescription() -> String {
        editRules
            .filter(\.enabled)
            .map(\.description)
            .joined(separator: "\n")
    }

    func addEntry(original: String, replacement: String) {
        entries.append(DictionaryEntry(original: original, replacement: replacement))
        save()
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func addRule(description: String) {
        editRules.append(EditRule(description: description))
        save()
    }

    func removeRule(at offsets: IndexSet) {
        editRules.remove(atOffsets: offsets)
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesURL)
        }
        if let data = try? encoder.encode(editRules) {
            try? data.write(to: rulesURL)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: entriesURL),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            entries = decoded
        }
        if let data = try? Data(contentsOf: rulesURL),
           let decoded = try? JSONDecoder().decode([EditRule].self, from: data) {
            editRules = decoded
        }
    }
}
