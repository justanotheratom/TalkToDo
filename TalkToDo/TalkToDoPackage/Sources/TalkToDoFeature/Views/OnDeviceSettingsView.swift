import SwiftUI
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct OnDeviceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settingsStore: ProcessingSettingsStore

    @State private var selectedModelSlug = ModelCatalog.defaultModel.slug
    @State private var downloadStates: [String: DownloadState] = [:]
    @State private var storage = ModelStorageService()
    @State private var downloadService = ModelDownloadService()
    @State private var isDownloading = false
    @State private var currentDownloadTask: Task<Void, Never>?

    public init(settingsStore: ProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
    }

    public var body: some View {
        Form {
            Section {
                Picker("Model", selection: $selectedModelSlug) {
                    ForEach(ModelCatalog.all) { model in
                        Text(model.displayName)
                            .tag(model.slug)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isDownloading)
                .onChange(of: selectedModelSlug) { oldValue, newValue in
                    handleModelSwitch(from: oldValue, to: newValue)
                }
            } header: {
                Text("LLM Model")
            } footer: {
                if isDownloading {
                    Text("Please wait for download to complete before switching models.")
                } else {
                    Text("Only one model is kept at a time to save space. Switching will delete the current model.")
                }
            }

            if let model = currentModel {
                Section {
                    LabeledContent("Size", value: "~\(model.estimatedSizeMB) MB")
                    LabeledContent("Platform", value: platformDisplayName(for: model.recommendedPlatform))

                    switch downloadStates[model.slug] ?? .notStarted {
                    case .notStarted:
                        Button("Download Model") {
                            downloadModel(model)
                        }
                        .buttonStyle(.borderedProminent)

                    case .inProgress(let progress):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Downloading...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: progress)

                            Button(role: .cancel) {
                                cancelDownload()
                            } label: {
                                Text("Cancel Download")
                            }
                            .buttonStyle(.bordered)
                        }

                    case .downloaded:
                        HStack {
                            StatusBadge(status: .installed)
                            Spacer()
                            Button("Delete", role: .destructive) {
                                deleteModel(model)
                            }
                            .buttonStyle(.bordered)
                        }

                    case .failed(let error):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button("Retry Download") {
                                downloadModel(model)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } header: {
                    Text("Model Details")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                        Text("What do the model sizes mean?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("700M is faster and uses less battery, while 1.2B is more accurate at understanding complex commands. Both run completely offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("On-Device Processing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled(isDownloading)
        .toolbar {
            if isDownloading {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelDownload()
                    }
                }
            }
        }
        .task {
            loadDownloadStates()
        }
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

    private func handleModelSwitch(from oldSlug: String, to newSlug: String) {
        guard oldSlug != newSlug else { return }

        // Delete old model if it exists
        if let oldModel = ModelCatalog.all.first(where: { $0.slug == oldSlug }),
           storage.isDownloaded(entry: oldModel) {
            do {
                try storage.deleteDownloadedModel(entry: oldModel)
                downloadStates[oldSlug] = .notStarted
            } catch {
                AppLogger.ui().logError(event: "onDeviceSettings:deleteOldModelFailed", error: error)
            }
        }

        // Auto-download new model if not already downloaded
        if let newModel = ModelCatalog.all.first(where: { $0.slug == newSlug }),
           !storage.isDownloaded(entry: newModel) {
            downloadModel(newModel)
        }
    }

    private func downloadModel(_ model: ModelCatalogEntry) {
        isDownloading = true
        downloadStates[model.slug] = .inProgress(progress: 0.0)

        currentDownloadTask = Task {
            do {
                let result = try await downloadService.downloadModel(entry: model) { progress in
                    Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        downloadStates[model.slug] = .inProgress(progress: progress)
                    }
                }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    downloadStates[model.slug] = .downloaded(localURL: result.localURL)
                    isDownloading = false
                    currentDownloadTask = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    downloadStates[model.slug] = .failed(error: error.localizedDescription)
                    isDownloading = false
                    currentDownloadTask = nil
                }
            }
        }
    }

    private func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        isDownloading = false

        // Reset download state for current model
        if let model = currentModel {
            downloadStates[model.slug] = .notStarted
        }
    }

    private func deleteModel(_ model: ModelCatalogEntry) {
        do {
            try storage.deleteDownloadedModel(entry: model)
            downloadStates[model.slug] = .notStarted
        } catch {
            AppLogger.ui().logError(event: "onDeviceSettings:deleteFailed", error: error)
        }
    }
}
