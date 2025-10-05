import Foundation
import Observation
import TalkToDoShared

/// Manages undo history using batch IDs
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class UndoManager {
    private var batchHistory: [String] = []  // Stack of batchIds
    private let maxHistorySize = 20

    public init() {}

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

        try eventStore.undoBatch(lastBatchId)

        AppLogger.data().log(event: "undo:performed", data: [
            "batchId": lastBatchId,
            "remainingBatches": batchHistory.count
        ])
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
