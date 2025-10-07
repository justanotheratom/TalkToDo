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

    // Card data for visual representation
    public let cardTitle: String?          // Primary title to show in card
    public let oldCardTitle: String?       // For renames: old title
    public let newCardTitle: String?       // For renames: new title
    public let isCardDeleted: Bool         // For deletes: strikethrough
    public let isCardCompleted: Bool       // For completions: checkbox state
    public let parentTitle: String?        // For context (created under...)

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
                self.description = "Created"
                self.details = nil

                // Card data
                self.cardTitle = payload.title
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = false
                self.isCardCompleted = false
                self.parentTitle = payload.parentId.flatMap { nodeTree.findNode(id: $0)?.title }

            case .renameNode:
                let payload = try JSONDecoder().decode(RenameNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "pencil.circle.fill"
                self.description = "Renamed"
                self.details = nil

                // Card data
                self.cardTitle = nil
                self.oldCardTitle = payload.oldTitle
                self.newCardTitle = payload.newTitle
                self.isCardDeleted = false
                self.isCardCompleted = false
                self.parentTitle = nil

            case .deleteNode:
                let payload = try JSONDecoder().decode(DeleteNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "trash.circle.fill"
                self.description = "Deleted"
                self.details = nil

                // Card data - get title from deleted node
                let node = nodeTree.findNode(id: payload.nodeId)
                self.cardTitle = node?.title ?? "Unknown"
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = true
                self.isCardCompleted = false
                self.parentTitle = nil

            case .reparentNode:
                let payload = try JSONDecoder().decode(ReparentNodePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "arrow.left.arrow.right.circle.fill"
                let node = nodeTree.findNode(id: payload.nodeId)
                let newParent = payload.newParentId.flatMap { nodeTree.findNode(id: $0) }
                self.description = newParent != nil ? "Moved" : "Moved to root"
                self.details = nil

                // Card data
                self.cardTitle = node?.title ?? "Unknown"
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = false
                self.isCardCompleted = false
                self.parentTitle = newParent?.title

            case .toggleComplete:
                let payload = try JSONDecoder().decode(ToggleCompletePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = payload.isCompleted ? "checkmark.circle.fill" : "circle"
                self.description = payload.isCompleted ? "Completed" : "Uncompleted"
                self.details = nil

                // Card data
                let node = nodeTree.findNode(id: payload.nodeId)
                self.cardTitle = node?.title ?? "Unknown"
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = false
                self.isCardCompleted = payload.isCompleted
                self.parentTitle = nil

            case .toggleCollapse:
                // Skip collapse events in changelog as they're UI-only
                let payload = try JSONDecoder().decode(ToggleCollapsePayload.self, from: event.payload)
                self.nodeId = payload.nodeId
                self.icon = "chevron.down.circle.fill"
                let node = nodeTree.findNode(id: payload.nodeId)
                self.description = node?.isCollapsed ?? false ? "Collapsed" : "Expanded"
                self.details = nil

                // Card data
                self.cardTitle = node?.title
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = false
                self.isCardCompleted = false
                self.parentTitle = nil

            case .none:
                self.nodeId = nil
                self.icon = "questionmark.circle.fill"
                self.description = "Unknown event"
                self.details = nil

                // Card data
                self.cardTitle = nil
                self.oldCardTitle = nil
                self.newCardTitle = nil
                self.isCardDeleted = false
                self.isCardCompleted = false
                self.parentTitle = nil
            }
        } catch {
            // Failed to decode payload
            self.nodeId = nil
            self.icon = "exclamationmark.triangle.fill"
            self.description = "Failed to decode event"
            self.details = "Type: \(event.type)"

            // Card data
            self.cardTitle = nil
            self.oldCardTitle = nil
            self.newCardTitle = nil
            self.isCardDeleted = false
            self.isCardCompleted = false
            self.parentTitle = nil
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
