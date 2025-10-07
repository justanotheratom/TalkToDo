import Foundation
import SwiftUI
import Observation
import TalkToDoShared

/// Manages undo history using batch IDs
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class UndoManager {
    private var batchHistory: [String] = []  // Stack of batchIds
    private let maxHistorySize = 20
    @ObservationIgnored private let changeTracker: ChangeTracker?

    public init(changeTracker: ChangeTracker? = nil) {
        self.changeTracker = changeTracker
    }

    // MARK: - Public API

    /// Record a new batch for undo
    public func recordBatch(_ batchId: String) {
        batchHistory.append(batchId)

        // Keep only last N batches
        if batchHistory.count > maxHistorySize {
            batchHistory.removeFirst()
        }

        AppLogger.data().log(event: "undo:recordBatch", data: [
            "batchId": batchId,
            "historySize": batchHistory.count
        ])
    }

    /// Undo the last batch
    public func undo(eventStore: EventStore) async throws {
        guard let lastBatchId = batchHistory.popLast() else {
            AppLogger.data().log(event: "undo:noBatches", data: [:])
            return
        }

        // Track highlights before undoing
        trackUndoHighlights(for: lastBatchId, eventStore: eventStore)

        try eventStore.undoBatch(lastBatchId)

        AppLogger.data().log(event: "undo:performed", data: [
            "batchId": lastBatchId,
            "remainingBatches": batchHistory.count
        ])
    }

    /// Fetch events for a batch and track undo highlights
    private func trackUndoHighlights(for batchId: String, eventStore: EventStore) {
        guard let tracker = changeTracker else { return }

        do {
            // Fetch events that will be undone
            let allEvents = try eventStore.fetchAll()
            let batchEvents = allEvents.filter { $0.batchId == batchId }

            // Extract node IDs from events
            var affectedNodeIds: [String] = []
            for event in batchEvents {
                guard let eventType = event.eventType else { continue }

                switch eventType {
                case .insertNode:
                    if let payload = try? JSONDecoder().decode(InsertNodePayload.self, from: event.payload) {
                        affectedNodeIds.append(payload.nodeId)
                    }
                case .renameNode:
                    if let payload = try? JSONDecoder().decode(RenameNodePayload.self, from: event.payload) {
                        affectedNodeIds.append(payload.nodeId)
                    }
                case .deleteNode:
                    if let payload = try? JSONDecoder().decode(DeleteNodePayload.self, from: event.payload) {
                        affectedNodeIds.append(payload.nodeId)
                    }
                case .reparentNode:
                    if let payload = try? JSONDecoder().decode(ReparentNodePayload.self, from: event.payload) {
                        affectedNodeIds.append(payload.nodeId)
                    }
                case .toggleCollapse, .toggleComplete:
                    break  // Don't highlight these
                }
            }

            if !affectedNodeIds.isEmpty {
                tracker.trackUndo(nodeIds: affectedNodeIds)
            }
        } catch {
            AppLogger.data().logError(event: "undo:trackHighlightsFailed", error: error)
        }
    }

    /// Check if undo is available
    public func canUndo() -> Bool {
        !batchHistory.isEmpty
    }

    /// Get the number of undoable batches
    public func undoCount() -> Int {
        batchHistory.count
    }

    /// Clear undo history
    public func clearHistory() {
        batchHistory.removeAll()
        AppLogger.data().log(event: "undo:clearHistory", data: [:])
    }
}

// MARK: - Environment Key

@available(iOS 18.0, macOS 15.0, *)
extension EnvironmentValues {
    @Entry public var undoManager: UndoManager? = nil
}
