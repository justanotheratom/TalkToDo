import Foundation
import TalkToDoShared

public struct OnDeviceVoicePipeline: VoiceProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case missingTranscript

        public var errorDescription: String? {
            switch self {
            case .missingTranscript:
                return "No transcript was captured for on-device processing."
            }
        }
    }

    private let llmService: LLMInferenceService

    public init(llmService: LLMInferenceService) {
        self.llmService = llmService
    }

    public func process(
        metadata: RecordingMetadata,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        guard let transcript = metadata.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            AppLogger.ui().log(event: "pipeline:onDevice:missingTranscript", data: [:])
            throw PipelineError.missingTranscript
        }

        AppLogger.ui().log(event: "pipeline:onDevice:start", data: [
            "transcriptLength": transcript.count,
            "hasNodeContext": nodeContext != nil
        ])

        let plan = try await llmService.generateOperations(
            from: transcript,
            nodeContext: nodeContext
        )

        AppLogger.ui().log(event: "pipeline:onDevice:success", data: [
            "operationCount": plan.operations.count
        ])

        return OperationGenerationResult(
            transcript: transcript,
            operations: plan.operations
        )
    }
}
