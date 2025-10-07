import Foundation

/// View model for displaying a changelog entry from a NodeEvent
@available(iOS 18.0, macOS 15.0, *)
public struct ChangelogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let type: NodeEvent.EventType
    public let nodeId: String?
    public let description: String
    public let icon: String
    public let details: String?

    @MainActor
    public init(from event: NodeEvent, nodeTree: NodeTree) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.type = event.eventType ?? .insertNode

        do {
            switch event.eventType {
            case .insertNode:
                let payload = try JSONDecoder().decode(InsertNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "plus.circle.fill"
                if let parentId = payload.parentId,
                   let parent = nodeTree.findNode(id: parentId) {
                    self.description = "Created '\(payload.title)' under '\(parent.title)'"
                } else {
                    self.description = "Created '\(payload.title)'"
                }
                self.details = nil

            case .renameNode:
                let payload = try JSONDecoder().decode(RenameNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "pencil.circle.fill"
                if let node = nodeTree.findNode(id: payload.nodeId) {
                    // Current title might not reflect old title if this is historical
                    // For now, we'll show what it was renamed to
                    self.description = "Renamed to '\(payload.newTitle)'"
                    self.details = "Node: \(payload.nodeId)"
                } else {
                    self.description = "Renamed to '\(payload.newTitle)'"
                    self.details = "Node: \(payload.nodeId)"
                }

            case .deleteNode:
                let payload = try JSONDecoder().decode(DeleteNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "trash.circle.fill"
                // Node won't exist in current tree, just show ID
                self.description = "Deleted node"
                self.details = "Node ID: \(payload.nodeId)"

            case .reparentNode:
                let payload = try JSONDecoder().decode(ReparentNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "arrow.left.arrow.right.circle.fill"
                if let node = nodeTree.findNode(id: payload.nodeId) {
                    if let newParentId = payload.newParentId,
                       let newParent = nodeTree.findNode(id: newParentId) {
                        self.description = "Moved '\(node.title)' under '\(newParent.title)'"
                    } else {
                        self.description = "Moved '\(node.title)' to root level"
                    }
                    self.details = nil
                } else {
                    self.description = "Moved node"
                    self.details = "Node ID: \(payload.nodeId)"
                }

            case .toggleComplete:
                let payload = try JSONDecoder().decode(ToggleCompletePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = payload.isCompleted ? "checkmark.circle.fill" : "circle"
                if let node = nodeTree.findNode(id: payload.nodeId) {
                    self.description = payload.isCompleted
                        ? "Completed '\(node.title)'"
                        : "Uncompleted '\(node.title)'"
                    self.details = nil
                } else {
                    self.description = payload.isCompleted ? "Completed node" : "Uncompleted node"
                    self.details = "Node ID: \(payload.nodeId)"
                }

            case .toggleCollapse:
                // Skip collapse events in changelog as they're UI-only
                let payload = try JSONDecoder().decode(ToggleCollapsePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "chevron.down.circle.fill"
                if let node = nodeTree.findNode(id: payload.nodeId) {
                    self.description = node.isCollapsed
                        ? "Collapsed '\(node.title)'"
                        : "Expanded '\(node.title)'"
                    self.details = nil
                } else {
                    self.description = "Toggled collapse"
                    self.details = "Node ID: \(payload.nodeId)"
                }

            case .none:
                self.nodeId = nil
                self.icon = "questionmark.circle.fill"
                self.description = "Unknown event"
                self.details = nil
            }
        } catch {
            // Failed to decode payload
            self.nodeId = nil
            self.icon = "exclamationmark.triangle.fill"
            self.description = "Failed to decode event"
            self.details = "Type: \(event.type)"
        }
    }

    /// Formatted timestamp for display
    public var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Absolute timestamp for detailed view
    public var absoluteTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    /// Icon color based on event type
    public var iconColor: String {
        switch type {
        case .insertNode:
            return "green"
        case .renameNode:
            return "orange"
        case .deleteNode:
            return "red"
        case .reparentNode:
            return "blue"
        case .toggleComplete:
            return "purple"
        case .toggleCollapse:
            return "gray"
        }
    }
}
