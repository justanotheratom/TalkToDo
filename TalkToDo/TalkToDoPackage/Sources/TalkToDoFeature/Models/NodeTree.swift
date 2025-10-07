import Foundation
import Observation
import TalkToDoShared

/// In-memory snapshot of the node hierarchy
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class NodeTree {
    public var rootNodes: [Node] = []
    private var nodeMap: [String: Node] = [:]  // Fast lookup by ID

    public init() {}

    // MARK: - Snapshot Initialization & Sync

    /// Called on app startup to rebuild snapshot from event log
    public func rebuildFromEvents(_ events: [NodeEvent]) {
        rootNodes = []
        nodeMap = [:]

        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        for event in sortedEvents {
            applyEvent(event)
        }

        AppLogger.data().log(event: "nodeTree:rebuild", data: [
            "eventCount": events.count,
            "nodeCount": nodeMap.count,
            "rootCount": rootNodes.count
        ])
    }

    /// Called every time a new event is appended to the log
    public func applyEvent(_ event: NodeEvent) {
        guard let eventType = event.eventType else {
            AppLogger.data().logError(
                event: "nodeTree:applyEvent:unknownType",
                error: NSError(domain: "NodeTree", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Unknown event type: \(event.type)"
                ])
            )
            return
        }

        do {
            switch eventType {
            case .insertNode:
                let payload = try JSONDecoder().decode(InsertNodePayload.self, from: event.payload)
                applyInsertNode(payload)
            case .renameNode:
                let payload = try JSONDecoder().decode(RenameNodePayload.self, from: event.payload)
                applyRenameNode(payload)
            case .deleteNode:
                let payload = try JSONDecoder().decode(DeleteNodePayload.self, from: event.payload)
                applyDeleteNode(payload)
            case .reparentNode:
                let payload = try JSONDecoder().decode(ReparentNodePayload.self, from: event.payload)
                applyReparentNode(payload)
            case .toggleCollapse:
                let payload = try JSONDecoder().decode(ToggleCollapsePayload.self, from: event.payload)
                applyToggleCollapse(payload)
            case .toggleComplete:
                let payload = try JSONDecoder().decode(ToggleCompletePayload.self, from: event.payload)
                applyToggleComplete(payload)
            }
        } catch {
            AppLogger.data().logError(event: "nodeTree:applyEvent:decodeFailed", error: error)
        }
    }

    // MARK: - Event Reducers

    private func applyInsertNode(_ payload: InsertNodePayload) {
        let newNode = Node(id: payload.nodeId, title: payload.title)
        nodeMap[payload.nodeId] = newNode

        if let parentId = payload.parentId,
           var parent = findNodeInTree(id: parentId) {
            let safePosition = min(payload.position, parent.children.count)
            parent.children.insert(newNode, at: safePosition)
            updateNode(parent)
        } else {
            // Insert at root level
            let safePosition = min(payload.position, rootNodes.count)
            rootNodes.insert(newNode, at: safePosition)
        }
    }

    private func applyRenameNode(_ payload: RenameNodePayload) {
        guard var node = findNodeInTree(id: payload.nodeId) else { return }
        node.title = payload.newTitle
        updateNode(node)
    }

    private func applyDeleteNode(_ payload: DeleteNodePayload) {
        // Mark node as deleted (soft delete for changelog)
        guard var node = findNodeInTree(id: payload.nodeId) else { return }
        node.isDeleted = true
        updateNode(node)

        // Also mark all descendants as deleted
        markDescendantsAsDeleted(node)
    }

    private func markDescendantsAsDeleted(_ node: Node) {
        for var child in node.children {
            child.isDeleted = true
            updateNode(child)
            markDescendantsAsDeleted(child)
        }
    }

    private func applyReparentNode(_ payload: ReparentNodePayload) {
        guard let node = findNodeInTree(id: payload.nodeId) else { return }

        // Remove from old parent
        if let oldParentId = findParent(of: payload.nodeId),
           var oldParent = findNodeInTree(id: oldParentId) {
            oldParent.children.removeAll { $0.id == payload.nodeId }
            updateNode(oldParent)
        } else {
            rootNodes.removeAll { $0.id == payload.nodeId }
        }

        // Insert into new parent
        if let newParentId = payload.newParentId,
           var newParent = findNodeInTree(id: newParentId) {
            let safePosition = min(payload.newPosition, newParent.children.count)
            newParent.children.insert(node, at: safePosition)
            updateNode(newParent)
        } else {
            let safePosition = min(payload.newPosition, rootNodes.count)
            rootNodes.insert(node, at: safePosition)
        }
    }

    private func applyToggleCollapse(_ payload: ToggleCollapsePayload) {
        guard var node = findNodeInTree(id: payload.nodeId) else { return }
        node.isCollapsed.toggle()
        updateNode(node)
    }

    private func applyToggleComplete(_ payload: ToggleCompletePayload) {
        guard var node = findNodeInTree(id: payload.nodeId) else { return }
        node.isCompleted = payload.isCompleted
        updateNode(node)
    }

    // MARK: - Tree Navigation Helpers

    private func findNodeInTree(id: String) -> Node? {
        nodeMap[id]
    }

    private func findParent(of nodeId: String) -> String? {
        for (parentId, parent) in nodeMap {
            if parent.children.contains(where: { $0.id == nodeId }) {
                return parentId
            }
        }
        return nil
    }

    private func updateNode(_ updatedNode: Node) {
        nodeMap[updatedNode.id] = updatedNode

        // Update in parent's children or root
        if let parentId = findParent(of: updatedNode.id),
           var parent = nodeMap[parentId] {
            if let index = parent.children.firstIndex(where: { $0.id == updatedNode.id }) {
                parent.children[index] = updatedNode
                updateNode(parent)  // Recursively update parent
            }
        } else {
            if let index = rootNodes.firstIndex(where: { $0.id == updatedNode.id }) {
                rootNodes[index] = updatedNode
            }
        }
    }

    private func removeFromMap(_ node: Node) {
        nodeMap.removeValue(forKey: node.id)
        for child in node.children {
            removeFromMap(child)
        }
    }

    // MARK: - Public Queries

    public func findNode(id: String) -> Node? {
        nodeMap[id]
    }

    public func allNodeCount() -> Int {
        nodeMap.count
    }
}
