import Foundation
import SwiftData

/// Event in the append-only log (SwiftData model)
@Model
public final class NodeEvent {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var type: String  // EventType as String for SwiftData
    public var payload: Data  // JSON-encoded event data
    public var batchId: String  // Groups events from same user interaction for undo

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: EventType,
        payload: Data,
        batchId: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type.rawValue
        self.payload = payload
        self.batchId = batchId
    }

    public enum EventType: String, Codable {
        case insertNode
        case renameNode
        case deleteNode
        case reparentNode
        case toggleCollapse
    }

    /// Get the event type enum from the stored string
    public var eventType: EventType? {
        EventType(rawValue: type)
    }
}

// MARK: - Event Payloads

public struct InsertNodePayload: Codable {
    public let nodeId: String  // 4-char hex
    public let title: String
    public let parentId: String?  // nil = root level
    public let position: Int  // Index in parent's children

    public init(nodeId: String, title: String, parentId: String?, position: Int) {
        self.nodeId = nodeId
        self.title = title
        self.parentId = parentId
        self.position = position
    }
}

public struct RenameNodePayload: Codable {
    public let nodeId: String
    public let newTitle: String

    public init(nodeId: String, newTitle: String) {
        self.nodeId = nodeId
        self.newTitle = newTitle
    }
}

public struct DeleteNodePayload: Codable {
    public let nodeId: String

    public init(nodeId: String) {
        self.nodeId = nodeId
    }
}

public struct ReparentNodePayload: Codable {
    public let nodeId: String
    public let newParentId: String?  // nil = move to root
    public let newPosition: Int

    public init(nodeId: String, newParentId: String?, newPosition: Int) {
        self.nodeId = nodeId
        self.newParentId = newParentId
        self.newPosition = newPosition
    }
}

public struct ToggleCollapsePayload: Codable {
    public let nodeId: String

    public init(nodeId: String) {
        self.nodeId = nodeId
    }
}
