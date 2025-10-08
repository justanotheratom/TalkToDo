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
    @ObservationIgnored private let operationExecutor: OperationExecutor
    @ObservationIgnored private let undoManager: UndoManager
    @ObservationIgnored private let changeTracker: ChangeTracker

    public init(
        eventStore: EventStore,
        pipeline: AnyVoiceProcessingPipeline,
        mode: ProcessingMode,
        undoManager: UndoManager,
        changeTracker: ChangeTracker
    ) {
        self.eventStore = eventStore
        self.pipeline = pipeline
        self.currentMode = mode
        self.operationExecutor = OperationExecutor(eventStore: eventStore, undoManager: undoManager)
        self.undoManager = undoManager
        self.changeTracker = changeTracker
    }

    public func updatePipeline(_ pipeline: AnyVoiceProcessingPipeline, mode: ProcessingMode) {
        self.pipeline = pipeline
        currentMode = mode
        AppLogger.ui().log(event: "voiceCoordinator:pipelineUpdated", data: [
            "mode": mode.rawValue
        ])
    }

    // MARK: - Voice Processing

    public func processRecording(
        metadata: RecordingMetadata,
        nodeContext: NodeContext? = nil
    ) async {
        let invocationID = UUID().uuidString
        let transcriptPreview = metadata.transcript ?? ""

        AppLogger.ui().log(event: "voiceCoordinator:processTranscriptStarted", data: [
            "transcriptLength": transcriptPreview.count,
            "hasNodeContext": nodeContext != nil,
            "invocationId": invocationID
        ])

        isProcessing = true
        processingError = nil
        processingTranscript = transcriptPreview.isEmpty ? nil : transcriptPreview

        do {
            AppLogger.ui().log(event: "voiceCoordinator:callingPipeline", data: [
                "mode": currentMode.rawValue,
                "invocationId": invocationID
            ])
            let context = makeProcessingContext(nodeContext: nodeContext)
            let result = try await pipeline.process(
                metadata: metadata,
                context: context
            )
            AppLogger.ui().log(event: "voiceCoordinator:pipelineReturned", data: [
                "operationCount": result.operations.count,
                "invocationId": invocationID
            ])

            AppLogger.ui().log(event: "voiceCoordinator:executingOperations", data: [
                "operationCount": result.operations.count,
                "invocationId": invocationID
            ])
            let summary = try operationExecutor.execute(operations: result.operations)
            AppLogger.ui().log(event: "voiceCoordinator:operationsApplied", data: [
                "eventCount": summary.eventCount,
                "batchId": summary.batchId,
                "invocationId": invocationID
            ])

            // Track changes for visual feedback
            var changes: [String: HighlightType] = [:]
            for operation in result.operations {
                guard let opType = operation.operationType else { continue }

                switch opType {
                case .insertNode:
                    changes[operation.nodeId] = .added
                case .renameNode:
                    changes[operation.nodeId] = .edited
                case .deleteNode:
                    changes[operation.nodeId] = .deleted
                case .reparentNode:
                    changes[operation.nodeId] = .edited
                }
            }
            if !changes.isEmpty {
                changeTracker.trackChanges(changes)
            }

            isProcessing = false
            processingTranscript = nil

            AppLogger.ui().log(event: "voiceCoordinator:processSuccess", data: [
                "operationCount": result.operations.count,
                "batchId": summary.batchId,
                "mode": currentMode.rawValue,
                "invocationId": invocationID
            ])
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
            AppLogger.ui().log(event: "voiceCoordinator:processFailedMode", data: [
                "mode": currentMode.rawValue,
                "invocationId": invocationID
            ])
            AppLogger.ui().logError(event: "voiceCoordinator:processFailed", error: error, data: [
                "invocationId": invocationID
            ])

            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    processingError = nil
                    processingTranscript = nil
                }
            }
        }
    }

    public func undo() async -> Bool {
        guard undoManager.canUndo() else {
            AppLogger.ui().log(event: "voiceCoordinator:undoUnavailable", data: [:])
            return false
        }

        do {
            try await undoManager.undo(eventStore: eventStore)
            AppLogger.ui().log(event: "voiceCoordinator:undoSuccess", data: [:])
            return true
        } catch {
            AppLogger.ui().logError(event: "voiceCoordinator:undoFailed", error: error)
            return false
        }
    }

    private func makeProcessingContext(nodeContext: NodeContext?) -> ProcessingContext {
        let history = (try? eventStore.eventLogSinceLaunch()) ?? []
        let snapshot = eventStore.currentSnapshot()
        return ProcessingContext(nodeContext: nodeContext, eventLog: history, nodeSnapshot: snapshot)
    }

}
