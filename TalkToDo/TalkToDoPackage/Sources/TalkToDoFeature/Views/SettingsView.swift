import SwiftUI
import SwiftData
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventStore) private var eventStore
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var fontPreference: FontPreference

    @Bindable private var settingsStore: VoiceProcessingSettingsStore

    @State private var selectedModelSlug = ModelCatalog.defaultModel.slug
    @State private var downloadStates: [String: DownloadState] = [:]
    @State private var storage = ModelStorageService()
    @State private var downloadService = ModelDownloadService()
    @State private var showDeleteDataAlert = false
    @State private var pasteFeedback: (message: String, isError: Bool)?

    public init(settingsStore: VoiceProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("AI Processing") {
                    let modeBinding = Binding(
                        get: { settingsStore.mode },
                        set: { settingsStore.update(mode: $0) }
                    )

                    Picker("Processing Mode", selection: modeBinding) {
                        ForEach(ProcessingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(settingsStore.mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let warning = settingsStore.mode.warningCopy {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if settingsStore.mode == .onDevice {
                        onDeviceControls
                    } else {
                        remoteControls
                    }
                }

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
                    Button(role: .destructive, action: { showDeleteDataAlert = true }) {
                        Label("Delete All User Data", systemImage: "trash")
                    }
                } footer: {
                    Text("This will permanently delete all your to-do items and reset the app.")
                }

                Section {
                    NavigationLink("Attributions") {
                        AttributionsView()
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Delete All Data?", isPresented: $showDeleteDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: deleteAllUserData)
            } message: {
                Text("This will permanently delete all your to-do items. This action cannot be undone.")
            }
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
        .task {
            loadDownloadStates()
        }
    }

    private var onDeviceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("LLM Model", selection: $selectedModelSlug) {
                ForEach(ModelCatalog.all) { model in
                    Text(model.displayName)
                        .tag(model.slug)
                }
            }
            .pickerStyle(.segmented)

            if let model = currentModel {
                HStack(alignment: .center) {
                    Text(modelSummary(for: model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    controlButton(for: model)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var remoteControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch settingsStore.geminiKeyStatus {
            case .missing:
                Text("No Gemini API key detected. Paste one to enable remote processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .present(let masked):
                Text("Gemini key linked: \(masked)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: pasteGeminiKey) {
                    Label("Paste API Key", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)

                if case .present = settingsStore.geminiKeyStatus {
                    Button(role: .destructive, action: clearGeminiKey) {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let feedback = pasteFeedback {
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(feedback.isError ? Color.red : Color.green)
            }
        }
        .padding(.top, 8)
    }

    private var currentModel: ModelCatalogEntry? {
        if let match = ModelCatalog.all.first(where: { $0.slug == selectedModelSlug }) {
            return match
        }
        if let first = ModelCatalog.all.first {
            selectedModelSlug = first.slug
            return first
        }
        return nil
    }

    private func modelSummary(for model: ModelCatalogEntry) -> String {
        let platform = platformDisplayName(for: model.recommendedPlatform)
        return "~\(model.estimatedSizeMB) MB • \(platform)"
    }

    @ViewBuilder
    private func controlButton(for model: ModelCatalogEntry) -> some View {
        switch downloadStates[model.slug] ?? .notStarted {
        case .notStarted:
            Button("Download") { downloadModel(model) }
                .buttonStyle(.borderedProminent)
        case .inProgress(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("Downloading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloaded:
            HStack(spacing: 12) {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Delete", role: .destructive) { deleteModel(model) }
                    .buttonStyle(.bordered)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Retry") { downloadModel(model) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func pasteGeminiKey() {
        #if os(iOS)
        let clipboard = UIPasteboard.general.string
        #else
        let clipboard = NSPasteboard.general.string(forType: .string)
        #endif

        guard let value = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            setPasteFeedback("Clipboard is empty", isError: true)
            return
        }

        settingsStore.updateGeminiAPIKey(value)
        setPasteFeedback("API key saved", isError: false)
    }

    private func clearGeminiKey() {
        settingsStore.updateGeminiAPIKey(nil)
        setPasteFeedback("API key removed", isError: false)
    }


    private func setPasteFeedback(_ message: String, isError: Bool) {
        pasteFeedback = (message, isError)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if pasteFeedback?.message == message {
                pasteFeedback = nil
            }
        }
    }

    private func platformDisplayName(for platform: ModelCatalogEntry.Platform) -> String {
        switch platform {
        case .iOS: return "Recommended for iPhone"
        case .macOS: return "Recommended for Mac"
        case .both: return "All devices"
        }
    }

    // MARK: - Model Management

    private func loadDownloadStates() {
        for model in ModelCatalog.all {
            if storage.isDownloaded(entry: model) {
                if let url = try? storage.expectedResourceURL(for: model) {
                    downloadStates[model.slug] = .downloaded(localURL: url)
                }
            } else {
                downloadStates[model.slug] = .notStarted
            }
        }
    }

    private func downloadModel(_ model: ModelCatalogEntry) {
        downloadStates[model.slug] = .inProgress(progress: 0.0)

        Task {
            do {
                let result = try await downloadService.downloadModel(entry: model) { progress in
                    Task { @MainActor in
                        downloadStates[model.slug] = .inProgress(progress: progress)
                    }
                }
                await MainActor.run {
                    downloadStates[model.slug] = .downloaded(localURL: result.localURL)
                }
            } catch {
                await MainActor.run {
                    downloadStates[model.slug] = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    private func deleteModel(_ model: ModelCatalogEntry) {
        do {
            try storage.deleteDownloadedModel(entry: model)
            downloadStates[model.slug] = .notStarted
        } catch {
            AppLogger.ui().logError(event: "settings:deleteFailed", error: error)
        }
    }

    // MARK: - Data Management

    private func deleteAllUserData() {
        guard let eventStore = eventStore else {
            AppLogger.ui().log(event: "settings:deleteAllDataSkipped", data: ["reason": "eventStoreNil"])
            return
        }

        do {
            try eventStore.deleteAllData()
            undoManager?.clearHistory()
            AppLogger.ui().log(event: "settings:allDataDeleted", data: [:])

            // Dismiss settings after deletion
            dismiss()
        } catch {
            AppLogger.ui().logError(event: "settings:deleteAllDataFailed", error: error)
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
