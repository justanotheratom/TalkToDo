import SwiftUI
import SwiftData

@available(iOS 18.0, macOS 15.0, *)
public struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventStore) private var eventStore
    @Environment(\.modelContext) private var modelContext

    @State private var changelogEntries: [ChangelogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading changelog...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error Loading Changelog", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if changelogEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Changes Yet", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("Your todo list changes will appear here")
                    }
                } else {
                    List {
                        ForEach(groupedEntries.keys.sorted(by: >), id: \.self) { date in
                            Section(header: Text(sectionTitle(for: date))) {
                                ForEach(groupedEntries[date] ?? []) { entry in
                                    ChangelogEntryRow(entry: entry)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Changelog")
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
            .task {
                await loadChangelog()
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadChangelog() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let store = eventStore else {
                errorMessage = "Event store not available"
                isLoading = false
                return
            }

            // Fetch all events
            let events = try store.fetchAll()

            // Filter out collapse events (UI noise)
            let filteredEvents = events.filter { event in
                event.eventType != .toggleCollapse
            }

            // Convert to changelog entries (reverse chronological)
            changelogEntries = filteredEvents
                .reversed()
                .map { event in
                    ChangelogEntry(from: event, nodeTree: store.nodeTree)
                }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Grouping

    private var groupedEntries: [Date: [ChangelogEntry]] {
        Dictionary(grouping: changelogEntries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                  date > weekAgo {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day of week
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

#Preview {
    ChangelogView()
        .environment(\.eventStore, nil)
}
