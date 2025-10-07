import Foundation
import TalkToDoShared

public struct GeminiVoicePipeline: VoiceProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyTranscript

        public var errorDescription: String? {
            switch self {
            case .emptyTranscript:
                return "Gemini returned an empty transcript."
            }
        }
    }

    private let client: any GeminiClientProtocol
    private let fallback: AnyVoiceProcessingPipeline

    public init(client: any GeminiClientProtocol, fallback: AnyVoiceProcessingPipeline) {
        self.client = client
        self.fallback = fallback
    }

    public func process(
        metadata: RecordingMetadata,
        nodeContext: NodeContext?
    ) async throws -> VoiceProcessingResult {
        do {
            let response = try await client.submitTask(
                audioURL: metadata.audioURL,
                transcript: metadata.transcript,
                localeIdentifier: metadata.localeIdentifier
            )

            let transcript = response.transcript ?? metadata.transcript ?? ""
            guard !transcript.isEmpty else {
                AppLogger.ui().log(event: "pipeline:gemini:emptyTranscript", data: [:])
                throw PipelineError.emptyTranscript
            }

            return VoiceProcessingResult(transcript: transcript, operations: response.operations)
        } catch {
            AppLogger.ui().logError(event: "pipeline:gemini:error", error: error)
            return try await fallback.process(metadata: metadata, nodeContext: nodeContext)
        }
    }
}
