import Foundation
import Observation
import SwiftData
import TalkToDoShared

/// Coordinates voice input → LLM → event store flow
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class VoiceInputCoordinator {
    public var isProcessing = false
    public var processingError: String?

    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private let llmService: LLMInferenceService
    @ObservationIgnored private let undoManager: UndoManager

    public init(
        eventStore: EventStore,
        llmService: LLMInferenceService,
        undoManager: UndoManager
    ) {
        self.eventStore = eventStore
        self.llmService = llmService
        self.undoManager = undoManager
    }

    // MARK: - Voice Processing

    /// Process voice transcript into node operations
    public func processTranscript(
        _ transcript: String,
        nodeContext: NodeContext? = nil
    ) async {
        isProcessing = true
        processingError = nil

        do {
            // Generate operations from LLM
            let plan = try await llmService.generateOperations(
                from: transcript,
                nodeContext: nodeContext
            )

            // Convert operations to events
            let batchId = NodeID.generateBatchID()
            let events = try convertOperationsToEvents(plan.operations, batchId: batchId)

            // Append to event store
            try eventStore.appendEvents(events, batchId: batchId)

            // Record for undo
            undoManager.recordBatch(batchId)

            isProcessing = false

            AppLogger.ui().log(event: "voiceCoordinator:processSuccess", data: [
                "operationCount": plan.operations.count,
                "batchId": batchId
            ])
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
            AppLogger.ui().logError(event: "voiceCoordinator:processFailed", error: error)
        }
    }

    // MARK: - Operation Conversion

    private func convertOperationsToEvents(
        _ operations: [Operation],
        batchId: String
    ) throws -> [NodeEvent] {
        var events: [NodeEvent] = []

        for operation in operations {
            guard let operationType = operation.operationType else {
                AppLogger.ui().log(event: "voiceCoordinator:unknownOperation", data: [
                    "type": operation.type
                ])
                continue
            }

            switch operationType {
            case .insertNode:
                guard let title = operation.title else {
                    AppLogger.ui().log(event: "voiceCoordinator:missingTitle", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let payload = InsertNodePayload(
                    nodeId: operation.nodeId,
                    title: title,
                    parentId: operation.parentId,
                    position: operation.position ?? 0
                )
                let payloadData = try JSONEncoder().encode(payload)
                let event = NodeEvent(
                    type: .insertNode,
                    payload: payloadData,
                    batchId: batchId
                )
                events.append(event)

            case .renameNode:
                guard let newTitle = operation.title else {
                    AppLogger.ui().log(event: "voiceCoordinator:missingTitle", data: [
                        "nodeId": operation.nodeId
                    ])
                    continue
                }

                let payload = RenameNodePayload(
                    nodeId: operation.nodeId,
                    newTitle: newTitle
                )
                let payloadData = try JSONEncoder().encode(payload)
                let event = NodeEvent(
                    type: .renameNode,
                    payload: payloadData,
                    batchId: batchId
                )
                events.append(event)

            case .deleteNode:
                let payload = DeleteNodePayload(nodeId: operation.nodeId)
                let payloadData = try JSONEncoder().encode(payload)
                let event = NodeEvent(
                    type: .deleteNode,
                    payload: payloadData,
                    batchId: batchId
                )
                events.append(event)

            case .reparentNode:
                let payload = ReparentNodePayload(
                    nodeId: operation.nodeId,
                    newParentId: operation.parentId,
                    newPosition: operation.position ?? 0
                )
                let payloadData = try JSONEncoder().encode(payload)
                let event = NodeEvent(
                    type: .reparentNode,
                    payload: payloadData,
                    batchId: batchId
                )
                events.append(event)
            }
        }

        return events
    }

    // MARK: - Undo

    public func undo() async -> Bool {
        guard undoManager.canUndo() else { return false }

        do {
            try await undoManager.undo(eventStore: eventStore)
            AppLogger.ui().log(event: "voiceCoordinator:undoSuccess", data: [:])
            return true
        } catch {
            processingError = "Undo failed: \(error.localizedDescription)"
            AppLogger.ui().logError(event: "voiceCoordinator:undoFailed", error: error)
            return false
        }
    }

    public func canUndo() -> Bool {
        undoManager.canUndo()
    }
}
