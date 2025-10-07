import Foundation
import TalkToDoShared

public struct OnDeviceTextPipeline: TextProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyText

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Please enter some text to convert into tasks."
            }
        }
    }

    private let llmService: LLMInferenceService

    public init(llmService: LLMInferenceService) {
        self.llmService = llmService
    }

    public func process(
        text: String,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.ui().log(event: "textPipeline:onDevice:empty", data: [:])
            throw PipelineError.emptyText
        }

        AppLogger.ui().log(event: "textPipeline:onDevice:start", data: [
            "length": trimmed.count
        ])

        let plan = try await llmService.generateOperations(
            from: trimmed,
            nodeContext: nodeContext
        )

        AppLogger.ui().log(event: "textPipeline:onDevice:success", data: [
            "operationCount": plan.operations.count
        ])

        return OperationGenerationResult(
            transcript: trimmed,
            operations: plan.operations
        )
    }
}
