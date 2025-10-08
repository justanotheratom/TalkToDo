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
                }

                Section {
                    NavigationLink("About") {
                        AboutView()
                    }

                    NavigationLink("Advanced") {
                        AdvancedSettingsView(settingsStore: settingsStore)
                    }
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
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
