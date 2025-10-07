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

    public init(
        eventStore: EventStore,
        pipeline: AnyVoiceProcessingPipeline,
        mode: ProcessingMode,
        undoManager: UndoManager
    ) {
        self.eventStore = eventStore
        self.pipeline = pipeline
        self.currentMode = mode
        self.operationExecutor = OperationExecutor(eventStore: eventStore, undoManager: undoManager)
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
            "hasNodeContext": nodeContext != nil
        ])

        isProcessing = true
        processingError = nil
        processingTranscript = transcriptPreview.isEmpty ? nil : transcriptPreview

        do {
            AppLogger.ui().log(event: "voiceCoordinator:callingPipeline", data: [
                "mode": currentMode.rawValue
            ])
            let context = makeProcessingContext(nodeContext: nodeContext)
            let result = try await pipeline.process(
                metadata: metadata,
                context: context
            )
            AppLogger.ui().log(event: "voiceCoordinator:pipelineReturned", data: [
                "operationCount": result.operations.count
            ])

            AppLogger.ui().log(event: "voiceCoordinator:executingOperations", data: [
                "operationCount": result.operations.count
            ])
            let summary = try operationExecutor.execute(operations: result.operations)
            AppLogger.ui().log(event: "voiceCoordinator:operationsApplied", data: [
                "eventCount": summary.eventCount,
                "batchId": summary.batchId
            ])

            isProcessing = false
            processingTranscript = nil

            AppLogger.ui().log(event: "voiceCoordinator:processSuccess", data: [
                "operationCount": result.operations.count,
                "batchId": summary.batchId,
                "mode": currentMode.rawValue
            ])
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
            AppLogger.ui().log(event: "voiceCoordinator:processFailedMode", data: [
                "mode": currentMode.rawValue
            ])
            AppLogger.ui().logError(event: "voiceCoordinator:processFailed", error: error)

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
