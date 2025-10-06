import Foundation
import SwiftData
import SwiftUI
import TalkToDoShared

/// Store managing the event log and coordinating with NodeTree
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class EventStore {
    private let modelContext: ModelContext
    private let nodeTree: NodeTree

    public init(modelContext: ModelContext, nodeTree: NodeTree) {
        self.modelContext = modelContext
        self.nodeTree = nodeTree
    }

    // MARK: - Event Appending

    /// Append a single event to the log
    public func appendEvent(_ event: NodeEvent) throws {
        modelContext.insert(event)
        try modelContext.save()
        nodeTree.applyEvent(event)

        AppLogger.data().log(event: "eventStore:append", data: [
            "type": event.type,
            "batchId": event.batchId
        ])
    }

    /// Append multiple events in a batch (same batchId)
    public func appendEvents(_ events: [NodeEvent], batchId: String) throws {
        for event in events {
            event.batchId = batchId
            modelContext.insert(event)
            nodeTree.applyEvent(event)
        }
        try modelContext.save()

        AppLogger.data().log(event: "eventStore:appendBatch", data: [
            "count": events.count,
            "batchId": batchId
        ])
    }

    // MARK: - Event Fetching

    /// Fetch all events from the log (sorted by timestamp)
    public func fetchAll() throws -> [NodeEvent] {
        let descriptor = FetchDescriptor<NodeEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch events since a specific timestamp
    public func fetchSince(_ timestamp: Date) throws -> [NodeEvent] {
        let descriptor = FetchDescriptor<NodeEvent>(
            predicate: #Predicate { $0.timestamp > timestamp },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch events by batchId
    private func fetchEventsByBatchId(_ batchId: String) throws -> [NodeEvent] {
        let descriptor = FetchDescriptor<NodeEvent>(
            predicate: #Predicate { $0.batchId == batchId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Undo

    /// Remove all events in a batch and rebuild snapshot
    public func undoBatch(_ batchId: String) throws {
        let batch = try fetchEventsByBatchId(batchId)

        guard !batch.isEmpty else {
            AppLogger.data().log(event: "eventStore:undo:batchNotFound", data: ["batchId": batchId])
            return
        }

        // Delete events
        for event in batch {
            modelContext.delete(event)
        }
        try modelContext.save()

        // Rebuild snapshot from remaining events
        let allEvents = try fetchAll()
        nodeTree.rebuildFromEvents(allEvents)

        AppLogger.data().log(event: "eventStore:undo", data: [
            "batchId": batchId,
            "eventsRemoved": batch.count
        ])
    }

    // MARK: - Initialization

    /// Initialize the node tree from the event log (call on app startup)
    public func initializeNodeTree() throws {
        let events = try fetchAll()
        nodeTree.rebuildFromEvents(events)

        AppLogger.data().log(event: "eventStore:initialize", data: [
            "eventCount": events.count,
            "nodeCount": nodeTree.allNodeCount()
        ])
    }

    // MARK: - Data Management

    /// Delete all events and reset the node tree
    public func deleteAllData() throws {
        try modelContext.delete(model: NodeEvent.self)
        try modelContext.save()
        nodeTree.rebuildFromEvents([])

        AppLogger.data().log(event: "eventStore:deleteAllData", data: [:])
    }
}

// MARK: - Environment Key

@available(iOS 18.0, macOS 15.0, *)
extension EnvironmentValues {
    @Entry public var eventStore: EventStore? = nil
}
