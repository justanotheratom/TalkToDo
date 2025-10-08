import SwiftUI
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct AdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventStore) private var eventStore
    @Environment(\.undoManager) private var undoManager

    @Bindable private var settingsStore: ProcessingSettingsStore

    @State private var showDeleteDataAlert = false
    @State private var storage = ModelStorageService()

    public init(settingsStore: ProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
    }

    public var body: some View {
        Form {
            Section("AI Processing") {
                let modeBinding = Binding(
                    get: { settingsStore.mode },
                    set: { newMode in
                        let oldMode = settingsStore.mode
                        settingsStore.update(mode: newMode)
                        handleModeSwitch(from: oldMode, to: newMode)
                    }
                )

                Picker("Mode", selection: modeBinding) {
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                NavigationLink {
                    if settingsStore.mode == .onDevice {
                        OnDeviceSettingsView(settingsStore: settingsStore)
                    } else {
                        RemoteSettingsView(settingsStore: settingsStore)
                    }
                } label: {
                    LabeledContent {
                        HStack(spacing: 8) {
                            StatusBadge(status: currentStatus)
                        }
                    } label: {
                        Text(currentConfigurationLabel)
                    }
                }
            }

            Section {
                Button(role: .destructive, action: { showDeleteDataAlert = true }) {
                    Label("Delete All User Data", systemImage: "trash")
                }
            } footer: {
                Text("This will permanently delete all your to-do items and reset the app. This action cannot be undone.")
            }
        }
        .navigationTitle("Advanced")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Delete All Data?", isPresented: $showDeleteDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deleteAllUserData)
        } message: {
            Text("This will permanently delete all your to-do items. This action cannot be undone.")
        }
    }

    private var currentConfigurationLabel: String {
        switch settingsStore.mode {
        case .onDevice:
            let model = ModelCatalog.defaultModel
            return model.displayName
        case .remoteGemini:
            return "Gemini 2.5 Flash Lite"
        }
    }

    private var currentStatus: StatusBadge.Status {
        switch settingsStore.mode {
        case .onDevice:
            let model = ModelCatalog.defaultModel
            if storage.isDownloaded(entry: model) {
                return .installed
            } else {
                return .notConfigured
            }
        case .remoteGemini:
            // Check environment variable first
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .ready
            }
            // Fall back to stored key
            let voiceProgram = settingsStore.resolvedVoiceProgram()
            switch settingsStore.apiKeyStatus(for: voiceProgram.modelConfig.apiKeyName) {
            case .present:
                return .ready
            case .missing:
                return .notConfigured
            }
        }
    }

    private func handleModeSwitch(from oldMode: ProcessingMode, to newMode: ProcessingMode) {
        guard oldMode != newMode else { return }

        // When switching to remote, delete all on-device models
        if newMode == .remoteGemini && oldMode == .onDevice {
            deleteAllOnDeviceModels()
        }
    }

    private func deleteAllOnDeviceModels() {
        for model in ModelCatalog.all {
            if storage.isDownloaded(entry: model) {
                do {
                    try storage.deleteDownloadedModel(entry: model)
                    AppLogger.ui().log(event: "advancedSettings:deletedModelOnModeSwitch", data: ["model": model.slug])
                } catch {
                    AppLogger.ui().logError(event: "advancedSettings:deleteModelFailed", error: error)
                }
            }
        }
    }

    private func deleteAllUserData() {
        guard let eventStore = eventStore else {
            AppLogger.ui().log(event: "advancedSettings:deleteAllDataSkipped", data: ["reason": "eventStoreNil"])
            return
        }

        do {
            try eventStore.deleteAllData()
            undoManager?.clearHistory()
            AppLogger.ui().log(event: "advancedSettings:allDataDeleted", data: [:])

            // Dismiss back to main settings
            dismiss()
        } catch {
            AppLogger.ui().logError(event: "advancedSettings:deleteAllDataFailed", error: error)
        }
    }
}
