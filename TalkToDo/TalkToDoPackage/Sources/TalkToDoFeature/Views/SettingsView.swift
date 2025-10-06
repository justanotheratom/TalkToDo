import SwiftUI
import SwiftData
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventStore) private var eventStore
    @Environment(\.undoManager) private var undoManager

    @State private var selectedModelSlug = ModelCatalog.defaultModel.slug
    @State private var downloadStates: [String: DownloadState] = [:]
    @State private var storage = ModelStorageService()
    @State private var downloadService = ModelDownloadService()
    @State private var showDeleteDataAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("LLM Model") {
                    ForEach(ModelCatalog.all) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModelSlug == model.slug,
                            downloadState: downloadStates[model.slug] ?? .notStarted,
                            onSelect: { selectedModelSlug = model.slug },
                            onDownload: { downloadModel(model) },
                            onDelete: { deleteModel(model) }
                        )
                    }
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

// MARK: - Model Row

@available(iOS 18.0, macOS 15.0, *)
private struct ModelRow: View {
    let model: ModelCatalogEntry
    let isSelected: Bool
    let downloadState: DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text("\(model.estimatedSizeMB) MB • \(recommendedPlatformText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Download/Delete button
            Group {
                switch downloadState {
                case .notStarted:
                    Button("Download", action: onDownload)
                        .buttonStyle(.bordered)

                case .inProgress(let progress):
                    ProgressView(value: progress, total: 1.0)
                        .frame(width: 60)

                case .downloaded:
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }

                case .failed:
                    Button("Retry", action: onDownload)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if case .downloaded = downloadState {
                onSelect()
            }
        }
    }

    private var recommendedPlatformText: String {
        switch model.recommendedPlatform {
        case .iOS:
            return "Recommended for iPhone"
        case .macOS:
            return "Recommended for Mac"
        case .both:
            return "All devices"
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
    SettingsView()
}
