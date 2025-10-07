import Foundation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct OperationExecutionSummary: Sendable {
    public let batchId: String
    public let eventCount: Int
}

@available(iOS 18.0, macOS 15.0, *)
@MainActor
public struct OperationExecutor {
    private let eventStore: EventStore
    private let undoManager: UndoManager

    public init(eventStore: EventStore, undoManager: UndoManager) {
        self.eventStore = eventStore
        self.undoManager = undoManager
    }

    public func execute(operations: [Operation]) throws -> OperationExecutionSummary {
        let batchId = NodeID.generateBatchID()
        let events = try convertOperationsToEvents(operations, batchId: batchId)

        try eventStore.appendEvents(events, batchId: batchId)
        undoManager.recordBatch(batchId)

        return OperationExecutionSummary(batchId: batchId, eventCount: events.count)
    }

    private func convertOperationsToEvents(_ operations: [Operation], batchId: String) throws -> [NodeEvent] {
        var events: [NodeEvent] = []
        var nodeIdMapping: [String: String] = [:]

        for operation in operations {
            guard let operationType = operation.operationType else {
                AppLogger.ui().log(event: "operationExecutor:unknownOperation", data: [
                    "type": operation.type
                ])
                continue
            }

            switch operationType {
            case .insertNode:
                guard let title = operation.title else {
                    AppLogger.ui().log(event: "operationExecutor:missingTitle", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let resolvedNodeId = resolveGeneratedNodeId(for: operation.nodeId, mapping: &nodeIdMapping)
                let resolvedParentId = resolveParentId(
                    operation.parentId,
                    mapping: nodeIdMapping
                )

                if let parentId = operation.parentId,
                   nodeIdMapping[parentId] == nil,
                   resolvedParentId == nil {
                    AppLogger.ui().log(event: "operationExecutor:parentNotResolved", data: [
                        "childNodeId": operation.nodeId,
                        "parentId": parentId,
                        "title": title
                    ])
                }

                let payload = InsertNodePayload(
                    nodeId: resolvedNodeId,
                    title: title,
                    parentId: resolvedParentId,
                    position: operation.position ?? 0
                )
                events.append(try makeEvent(type: .insertNode, payload: payload, batchId: batchId))

            case .renameNode:
                guard let newTitle = operation.title else {
                    AppLogger.ui().log(event: "operationExecutor:missingTitle", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let targetId = resolveNodeId(operation.nodeId, mapping: nodeIdMapping)

                // Get old title from current node state
                let oldTitle = eventStore.nodeTree.findNode(id: targetId)?.title ?? ""

                let payload = RenameNodePayload(nodeId: targetId, oldTitle: oldTitle, newTitle: newTitle)
                events.append(try makeEvent(type: .renameNode, payload: payload, batchId: batchId))

            case .deleteNode:
                let targetId = resolveNodeId(operation.nodeId, mapping: nodeIdMapping)
                let payload = DeleteNodePayload(nodeId: targetId)
                events.append(try makeEvent(type: .deleteNode, payload: payload, batchId: batchId))

            case .reparentNode:
                guard let parentId = operation.parentId else {
                    AppLogger.ui().log(event: "operationExecutor:missingParent", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let targetId = resolveNodeId(operation.nodeId, mapping: nodeIdMapping)
                let resolvedParentId = resolveParentId(parentId, mapping: nodeIdMapping)

                let payload = ReparentNodePayload(
                    nodeId: targetId,
                    newParentId: resolvedParentId,
                    newPosition: operation.position ?? 0
                )
                events.append(try makeEvent(type: .reparentNode, payload: payload, batchId: batchId))
            }
        }

        return events
    }

    private func resolveGeneratedNodeId(
        for originalId: String,
        mapping: inout [String: String]
    ) -> String {
        if let existing = mapping[originalId] {
            return existing
        }

        let generated = NodeID.generate()
        mapping[originalId] = generated
        return generated
    }

    private func resolveNodeId(
        _ nodeId: String,
        mapping: [String: String]
    ) -> String {
        mapping[nodeId] ?? nodeId
    }

    private func resolveParentId(
        _ parentId: String?,
        mapping: [String: String]
    ) -> String? {
        guard let parentId else { return nil }
        if let mapped = mapping[parentId] {
            return mapped
        }
        return parentId
    }

    private func makeEvent<P: Encodable>(type: NodeEvent.EventType, payload: P, batchId: String) throws -> NodeEvent {
        let payloadData = try JSONEncoder().encode(payload)
        return NodeEvent(
            type: type,
            payload: payloadData,
            batchId: batchId
        )
    }
}
