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

    public init(client: any GeminiClientProtocol) {
        self.client = client
    }

    public func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        do {
            let response = try await client.submitTask(
                audio: metadata.audioData.flatMap { data in
                    let format = metadata.audioFormat ?? "wav"
                    return GeminiAudioPayload(data: data, format: format)
                },
                transcript: metadata.transcript,
                localeIdentifier: metadata.localeIdentifier,
                eventLog: context.eventLog,
                nodeSnapshot: context.nodeSnapshot,
                nodeContext: context.nodeContext
            )

            let transcript = response.transcript ?? metadata.transcript ?? ""
            guard !transcript.isEmpty else {
                AppLogger.ui().log(event: "pipeline:gemini:emptyTranscript", data: [:])
                throw PipelineError.emptyTranscript
            }

            return OperationGenerationResult(transcript: transcript, operations: response.operations)
        } catch {
            AppLogger.ui().logError(event: "pipeline:gemini:error", error: error)
            throw error
        }
    }
}
