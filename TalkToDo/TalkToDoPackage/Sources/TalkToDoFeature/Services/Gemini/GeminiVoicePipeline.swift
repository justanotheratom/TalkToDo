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

    private let client: GeminiAPIClient
    private let fallback: AnyVoiceProcessingPipeline

    public init(client: GeminiAPIClient, fallback: AnyVoiceProcessingPipeline) {
        self.client = client
        self.fallback = fallback
    }

    public func process(
        metadata: RecordingMetadata,
        nodeContext: NodeContext?
    ) async throws -> VoiceProcessingResult {
        guard let audioURL = metadata.audioURL else {
            AppLogger.ui().log(event: "pipeline:gemini:missingAudio", data: [:])
            return try await fallback.process(metadata: metadata, nodeContext: nodeContext)
        }

        do {
            let response = try await client.submitTask(
                audioURL: audioURL,
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
