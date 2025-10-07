import Foundation
import Observation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class TextInputCoordinator {
    public var isProcessing = false
    public var processingError: String?
    public var processingText: String?

    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private var pipeline: AnyTextProcessingPipeline
    @ObservationIgnored private var currentMode: ProcessingMode
    @ObservationIgnored private let operationExecutor: OperationExecutor
    @ObservationIgnored private let changeTracker: ChangeTracker

    public init(
        eventStore: EventStore,
        pipeline: AnyTextProcessingPipeline,
        mode: ProcessingMode,
        undoManager: UndoManager,
        changeTracker: ChangeTracker
    ) {
        self.eventStore = eventStore
        self.pipeline = pipeline
        self.currentMode = mode
        self.operationExecutor = OperationExecutor(eventStore: eventStore, undoManager: undoManager)
        self.changeTracker = changeTracker
    }

    public func updatePipeline(_ pipeline: AnyTextProcessingPipeline, mode: ProcessingMode) {
        self.pipeline = pipeline
        currentMode = mode
        AppLogger.ui().log(event: "textCoordinator:pipelineUpdated", data: [
            "mode": mode.rawValue
        ])
    }

    public func processText(
        _ text: String,
        nodeContext: NodeContext? = nil
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.ui().log(event: "textCoordinator:processStarted", data: [
            "length": trimmed.count,
            "mode": currentMode.rawValue
        ])

        isProcessing = true
        processingError = nil
        processingText = trimmed

        do {
            let context = makeProcessingContext(nodeContext: nodeContext)
            let result = try await pipeline.process(text: trimmed, context: context)
            let summary = try operationExecutor.execute(operations: result.operations)

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
            processingText = nil

            AppLogger.ui().log(event: "textCoordinator:processSuccess", data: [
                "operationCount": result.operations.count,
                "batchId": summary.batchId,
                "mode": currentMode.rawValue
            ])
        } catch {
            isProcessing = false
            processingError = error.localizedDescription
            AppLogger.ui().logError(event: "textCoordinator:processFailed", error: error)

            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    processingError = nil
                    processingText = nil
                }
            }
        }
    }

    private func makeProcessingContext(nodeContext: NodeContext?) -> ProcessingContext {
        let history = (try? eventStore.eventLogSinceLaunch()) ?? []
        let snapshot = eventStore.currentSnapshot()
        return ProcessingContext(nodeContext: nodeContext, eventLog: history, nodeSnapshot: snapshot)
    }
}
