import SwiftUI

struct DictionaryStyleView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var dictionary = PersonalDictionary.shared

    @State private var newOriginal = ""
    @State private var newReplacement = ""
    @State private var newRule = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                styleSection
                Divider()
                dictionarySection
                Divider()
                editRulesSection
            }
            .padding(20)
        }
    }

    // MARK: - Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("style.title"), systemImage: "paintbrush")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(LanguageStyle.allCases, id: \.self) { style in
                    StylePresetCard(
                        style: style,
                        isSelected: settings.languageStyle == style
                    ) {
                        settings.languageStyle = style
                        settings.customStylePrompt = style.defaultPrompt
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("style.prompt"))
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $settings.customStylePrompt)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 68)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                Text(L("style.prompt_help"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Dictionary

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("dict.title"), systemImage: "character.book.closed")
                .font(.headline)
            Text(L("dict.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(L("dict.original"), text: $newOriginal)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField(L("dict.replacement"), text: $newReplacement)
                    .textFieldStyle(.roundedBorder)
                Button(L("common.add")) {
                    guard !newOriginal.isEmpty, !newReplacement.isEmpty else { return }
                    dictionary.addEntry(original: newOriginal, replacement: newReplacement)
                    newOriginal = ""
                    newReplacement = ""
                }
                .controlSize(.small)
            }

            if dictionary.entries.isEmpty {
                emptyHint(L("dict.empty"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dictionary.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text(entry.original)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .trailing)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(entry.replacement)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            deleteButton { dictionary.removeEntry(at: IndexSet(integer: index)) }
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        if index < dictionary.entries.count - 1 { Divider().padding(.horizontal, 10) }
                    }
                }
                .listCard()
            }
        }
    }

    // MARK: - Edit Rules

    private var editRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("rules.title"), systemImage: "list.bullet.rectangle")
                .font(.headline)
            Text(L("rules.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(L("rules.placeholder"), text: $newRule)
                    .textFieldStyle(.roundedBorder)
                Button(L("common.add")) {
                    guard !newRule.isEmpty else { return }
                    dictionary.addRule(description: newRule)
                    newRule = ""
                }
                .controlSize(.small)
            }

            if dictionary.editRules.isEmpty {
                emptyHint(L("rules.empty"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dictionary.editRules.enumerated()), id: \.element.id) { index, rule in
                        HStack {
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rule.enabled ? .green : .secondary)
                                .font(.caption)
                            Text(rule.description)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            deleteButton { dictionary.removeRule(at: IndexSet(integer: index)) }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        if index < dictionary.editRules.count - 1 { Divider().padding(.horizontal, 10) }
                    }
                }
                .listCard()
            }
        }
    }

    // MARK: - Helpers

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 36)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Style Preset Card

private struct StylePresetCard: View {
    let style: LanguageStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: style.icon)
                        .font(.system(size: 13))
                    Text(style.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(style.defaultPrompt)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List Card Modifier

private struct ListCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

private extension View {
    func listCard() -> some View {
        modifier(ListCardModifier())
    }
}
