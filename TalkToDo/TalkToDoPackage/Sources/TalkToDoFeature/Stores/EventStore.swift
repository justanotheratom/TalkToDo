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
    public let nodeTree: NodeTree
    private let launchTimestamp: Date
    private let eventHistoryLimit = 20

    public init(modelContext: ModelContext, nodeTree: NodeTree) {
        self.modelContext = modelContext
        self.nodeTree = nodeTree
        self.launchTimestamp = Date()
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

    // MARK: - Event History

    public func eventLogSinceLaunch() throws -> [EventLogEntry] {
        let descriptor = FetchDescriptor<NodeEvent>(
            predicate: #Predicate { $0.timestamp >= launchTimestamp },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let events = try modelContext.fetch(descriptor)

        let entries: [EventLogEntry] = events.compactMap { event -> EventLogEntry? in
            guard let type = event.eventType else { return nil }
            do {
                switch type {
                case .insertNode:
                    let payload = try JSONDecoder().decode(InsertNodePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: payload.title,
                        parentId: payload.parentId,
                        position: payload.position,
                        newTitle: nil,
                        newParentId: nil,
                        newPosition: nil
                    )
                case .renameNode:
                    let payload = try JSONDecoder().decode(RenameNodePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: nil,
                        parentId: nil,
                        position: nil,
                        newTitle: payload.newTitle,
                        newParentId: nil,
                        newPosition: nil
                    )
                case .deleteNode:
                    let payload = try JSONDecoder().decode(DeleteNodePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: nil,
                        parentId: nil,
                        position: nil,
                        newTitle: nil,
                        newParentId: nil,
                        newPosition: nil
                    )
                case .reparentNode:
                    let payload = try JSONDecoder().decode(ReparentNodePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: nil,
                        parentId: nil,
                        position: nil,
                        newTitle: nil,
                        newParentId: payload.newParentId,
                        newPosition: payload.newPosition
                    )
                case .toggleCollapse:
                    let payload = try JSONDecoder().decode(ToggleCollapsePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: nil,
                        parentId: nil,
                        position: nil,
                        newTitle: nil,
                        newParentId: nil,
                        newPosition: nil
                    )
                case .toggleComplete:
                    let payload = try JSONDecoder().decode(ToggleCompletePayload.self, from: event.payload)
                    return EventLogEntry(
                        timestamp: event.timestamp,
                        type: type,
                        nodeId: payload.nodeId,
                        title: nil,
                        parentId: nil,
                        position: nil,
                        newTitle: nil,
                        newParentId: nil,
                        newPosition: nil
                    )
                }
            } catch {
                AppLogger.data().logError(event: "eventStore:historyDecodeFailed", error: error, data: [
                    "eventType": event.type
                ])
                return nil
            }
        }

        if entries.count > eventHistoryLimit {
            AppLogger.data().log(event: "eventStore:historyTrimmed", data: [
                "requested": entries.count,
                "limit": eventHistoryLimit
            ])
        }

        return Array(entries.suffix(eventHistoryLimit))
    }

    public func currentSnapshot() -> [SnapshotNode] {
        nodeTree.rootNodes.map { node in
            SnapshotNode(node: node)
        }
    }
}

// MARK: - Environment Key

@available(iOS 18.0, macOS 15.0, *)
extension EnvironmentValues {
    @Entry public var eventStore: EventStore? = nil
}

public struct EventLogEntry: Codable, Sendable {
    public let timestamp: Date
    public let type: NodeEvent.EventType
    public let nodeId: String?
    public let title: String?
    public let parentId: String?
    public let position: Int?
    public let newTitle: String?
    public let newParentId: String?
    public let newPosition: Int?

    public init(
        timestamp: Date,
        type: NodeEvent.EventType,
        nodeId: String?,
        title: String?,
        parentId: String?,
        position: Int?,
        newTitle: String?,
        newParentId: String?,
        newPosition: Int?
    ) {
        self.timestamp = timestamp
        self.type = type
        self.nodeId = nodeId
        self.title = title
        self.parentId = parentId
        self.position = position
        self.newTitle = newTitle
        self.newParentId = newParentId
        self.newPosition = newPosition
    }
}

public struct SnapshotNode: Codable, Sendable {
    public let id: String
    public let title: String
    public let isCollapsed: Bool
    public let children: [SnapshotNode]

    public init(id: String, title: String, isCollapsed: Bool, children: [SnapshotNode]) {
        self.id = id
        self.title = title
        self.isCollapsed = isCollapsed
        self.children = children
    }

    init(node: Node) {
        self.init(
            id: node.id,
            title: node.title,
            isCollapsed: node.isCollapsed,
            children: node.children.map { SnapshotNode(node: $0) }
        )
    }
}
