import SwiftUI

struct HistoryStatsView: View {
    @StateObject private var history = InputHistory.shared
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            statsCards
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            historyList
        }
    }

    // MARK: - Stats

    private var statsCards: some View {
        let s = history.stats
        return HStack(spacing: 10) {
            statCard(value: "\(s.totalInputs)", label: L("history.total"), icon: "text.bubble")
            statCard(value: "\(s.todayInputs)", label: L("history.today"), icon: "calendar")
            statCard(value: formatChars(s.totalProcessedChars), label: L("history.chars"), icon: "character.cursor.ibeam")
            statCard(value: s.totalRawChars > 0 ? "\(Int(s.efficiencyRatio * 100))%" : "—", label: L("history.saved"), icon: "bolt")
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func formatChars(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1fk", Double(count) / 1000) }
        return "\(count)"
    }

    // MARK: - History List

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField(L("history.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                if !history.records.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label(L("history.clear_all"), systemImage: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .alert(L("history.clear_confirm"), isPresented: $showClearConfirm) {
                        Button(L("common.cancel"), role: .cancel) {}
                        Button(L("common.clear"), role: .destructive) { history.clearAll() }
                    } message: {
                        Text(L("common.cannot_undo"))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty
                         ? L("history.empty")
                         : L("history.no_match"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRecords) { record in
                            historyRow(record)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    private var filteredRecords: [InputRecord] {
        if searchText.isEmpty { return history.records }
        let query = searchText.lowercased()
        return history.records.filter {
            $0.processedText.lowercased().contains(query) ||
            $0.rawText.lowercased().contains(query)
        }
    }

    private func historyRow(_ record: InputRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.processedText)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(formatDate(record.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if record.wasProcessed && record.rawCharCount != record.processedCharCount {
                        let delta = record.rawCharCount - record.processedCharCount
                        let label = delta > 0
                            ? String(format: L("history.chars_saved_fmt"), delta)
                            : String(format: L("history.chars_added_fmt"), abs(delta))
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(delta > 0 ? .green : .orange)
                    }
                }
            }

            VStack(spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.processedText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("common.copy"))

                Button {
                    history.deleteRecord(record.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_today") + " " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return L("history.date_yesterday") + " " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
            return formatter.string(from: date)
        }
    }
}
