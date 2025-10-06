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
    public var processingTranscript: String?

    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private var pipeline: AnyVoiceProcessingPipeline
    @ObservationIgnored private var currentMode: ProcessingMode
    @ObservationIgnored private let undoManager: UndoManager

    public init(
        eventStore: EventStore,
        pipeline: AnyVoiceProcessingPipeline,
        mode: ProcessingMode,
        undoManager: UndoManager
    ) {
        self.eventStore = eventStore
        self.pipeline = pipeline
        self.currentMode = mode
        self.undoManager = undoManager
    }

    public func updatePipeline(_ pipeline: AnyVoiceProcessingPipeline, mode: ProcessingMode) {
        self.pipeline = pipeline
        currentMode = mode
        AppLogger.ui().log(event: "voiceCoordinator:pipelineUpdated", data: [
            "mode": mode.rawValue
        ])
    }

    // MARK: - Voice Processing

    /// Process voice transcript into node operations
    public func processRecording(
        metadata: RecordingMetadata,
        nodeContext: NodeContext? = nil
    ) async {
        let transcriptPreview = metadata.transcript ?? ""
        let audioURL = metadata.audioURL
        defer {
            if let audioURL,
               FileManager.default.fileExists(atPath: audioURL.path) {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        AppLogger.ui().log(event: "voiceCoordinator:processTranscriptStarted", data: [
            "transcriptLength": transcriptPreview.count,
            "hasNodeContext": nodeContext != nil,
            "transcript": transcriptPreview
        ])
        isProcessing = true
        processingError = nil
        processingTranscript = transcriptPreview.isEmpty ? nil : transcriptPreview

        do {
            AppLogger.ui().log(event: "voiceCoordinator:callingPipeline", data: [
                "mode": currentMode.rawValue
            ])
            let result = try await pipeline.process(
                metadata: metadata,
                nodeContext: nodeContext
            )
            AppLogger.ui().log(event: "voiceCoordinator:pipelineReturned", data: [
                "operationCount": result.operations.count
            ])

            // Convert operations to events
            let batchId = NodeID.generateBatchID()
            AppLogger.ui().log(event: "voiceCoordinator:convertingOperations", data: [
                "operationCount": result.operations.count
            ])
            let events = try convertOperationsToEvents(result.operations, batchId: batchId)
            AppLogger.ui().log(event: "voiceCoordinator:operationsConverted", data: [
                "eventCount": events.count
            ])

            // Append to event store
            AppLogger.ui().log(event: "voiceCoordinator:appendingEvents", data: [
                "eventCount": events.count
            ])
            try eventStore.appendEvents(events, batchId: batchId)
            AppLogger.ui().log(event: "voiceCoordinator:eventsAppended", data: [:])

            // Record for undo
            undoManager.recordBatch(batchId)

            isProcessing = false
            processingTranscript = nil

            AppLogger.ui().log(event: "voiceCoordinator:processSuccess", data: [
                "operationCount": result.operations.count,
                "batchId": batchId,
                "mode": currentMode.rawValue
            ])
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
            // Keep transcript visible for error state
            AppLogger.ui().log(event: "voiceCoordinator:processFailedMode", data: [
                "mode": currentMode.rawValue
            ])
            AppLogger.ui().logError(event: "voiceCoordinator:processFailed", error: error)

            // Clear error after delay
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    processingError = nil
                    processingTranscript = nil
                }
            }
        }
    }

    // MARK: - Operation Conversion

    private func convertOperationsToEvents(
        _ operations: [Operation],
        batchId: String
    ) throws -> [NodeEvent] {
        var events: [NodeEvent] = []
        var createdNodeIds = Set<String>()

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

                // Validate parentId if specified
                if let parentId = operation.parentId, !createdNodeIds.contains(parentId) {
                    AppLogger.ui().log(event: "voiceCoordinator:invalidParentId", data: [
                        "nodeId": operation.nodeId,
                        "parentId": parentId,
                        "title": title,
                        "reason": "Parent ID does not exist in earlier operations - setting to null"
                    ])
                    // Set parentId to null to make it a root node instead
                    let uniqueNodeId = NodeID.generate()
                    createdNodeIds.insert(uniqueNodeId)

                    let payload = InsertNodePayload(
                        nodeId: uniqueNodeId,
                        title: title,
                        parentId: nil,
                        position: operation.position ?? 0
                    )
                    let payloadData = try JSONEncoder().encode(payload)
                    let event = NodeEvent(
                        type: .insertNode,
                        payload: payloadData,
                        batchId: batchId
                    )
                    events.append(event)
                } else {
                    // Generate unique ID instead of using LLM's potentially duplicate ID
                    let uniqueNodeId = NodeID.generate()
                    createdNodeIds.insert(uniqueNodeId)

                    let payload = InsertNodePayload(
                        nodeId: uniqueNodeId,
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
                }

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
