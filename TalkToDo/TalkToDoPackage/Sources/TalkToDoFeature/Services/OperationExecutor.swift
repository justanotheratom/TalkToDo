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
        var createdNodeIds = Set<String>()

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

                if let parentId = operation.parentId, !createdNodeIds.contains(parentId) {
                    AppLogger.ui().log(event: "operationExecutor:invalidParentId", data: [
                        "nodeId": operation.nodeId,
                        "parentId": parentId,
                        "title": title,
                        "reason": "Parent ID does not exist in earlier operations - setting to null"
                    ])
                    let uniqueNodeId = NodeID.generate()
                    createdNodeIds.insert(uniqueNodeId)

                    let payload = InsertNodePayload(
                        nodeId: uniqueNodeId,
                        title: title,
                        parentId: nil,
                        position: operation.position ?? 0
                    )
                    events.append(try makeEvent(type: .insertNode, payload: payload, batchId: batchId))
                } else {
                    let uniqueNodeId = NodeID.generate()
                    createdNodeIds.insert(uniqueNodeId)

                    let payload = InsertNodePayload(
                        nodeId: uniqueNodeId,
                        title: title,
                        parentId: operation.parentId,
                        position: operation.position ?? 0
                    )
                    events.append(try makeEvent(type: .insertNode, payload: payload, batchId: batchId))
                }

            case .renameNode:
                guard let newTitle = operation.title else {
                    AppLogger.ui().log(event: "operationExecutor:missingTitle", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let payload = RenameNodePayload(nodeId: operation.nodeId, newTitle: newTitle)
                events.append(try makeEvent(type: .renameNode, payload: payload, batchId: batchId))

            case .deleteNode:
                let payload = DeleteNodePayload(nodeId: operation.nodeId)
                events.append(try makeEvent(type: .deleteNode, payload: payload, batchId: batchId))

            case .reparentNode:
                guard let parentId = operation.parentId else {
                    AppLogger.ui().log(event: "operationExecutor:missingParent", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let payload = ReparentNodePayload(
                    nodeId: operation.nodeId,
                    newParentId: parentId,
                    newPosition: operation.position ?? 0
                )
                events.append(try makeEvent(type: .reparentNode, payload: payload, batchId: batchId))
            }
        }

        return events
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
