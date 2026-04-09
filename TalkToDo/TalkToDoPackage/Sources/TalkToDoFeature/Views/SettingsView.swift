import SwiftUI
import SwiftData
import Observation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fontPreference: FontPreference

    @Bindable private var settingsStore: VoiceProcessingSettingsStore

    public init(settingsStore: VoiceProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Font", selection: $fontPreference.selectedFont) {
                        ForEach(AppFont.allCases, id: \.self) { font in
                            Text(font.displayName)
                                .font(font.body)
                                .tag(font)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Sample preview of selected font")
                        .font(fontPreference.selectedFont.body)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink("History") {
                        ChangelogView()
                    }
                    .accessibilityIdentifier("history_link")
                }

                Section {
                    NavigationLink("About") {
                        AboutView()
                    }

                    NavigationLink("Advanced") {
                        AdvancedSettingsView(settingsStore: settingsStore)
                    }
                    .accessibilityIdentifier("advanced_link")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings_done_button")
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings_done_button")
                }
                #endif
            }
        }
    }
}

// MARK: - Download State

public enum DownloadState: Equatable {
    case notStarted
    case inProgress(progress: Double)
    case downloaded(localURL: URL)
    case failed(error: String)
}

#Preview {
    SettingsView(settingsStore: VoiceProcessingSettingsStore())
}
