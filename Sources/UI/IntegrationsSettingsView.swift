import SwiftUI

struct IntegrationsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(L("settings.developer_interface")) {
                Toggle(isOn: $settings.developerInterfaceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.developer_interface"))
                        Text(L("settings.developer_interface_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("HTTP") {
                LabeledContent(L("settings.developer_http_address")) {
                    Text("127.0.0.1:\(settings.developerHTTPPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent(L("settings.developer_http_token")) {
                    Text(settings.developerHTTPToken)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button(L("settings.developer_reset_token")) {
                    settings.resetDeveloperHTTPToken()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
