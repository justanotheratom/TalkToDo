import Foundation
import TalkToDoShared

public struct RemoteVoicePipeline: VoiceProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyTranscript

        public var errorDescription: String? {
            switch self {
            case .emptyTranscript:
                return "Remote API returned an empty transcript."
            }
        }
    }

    private let program: any AIProgram
    private let apiKeyResolver: APIKeyResolver

    public init(program: any AIProgram, apiKeyResolver: APIKeyResolver = DefaultAPIKeyResolver()) {
        self.program = program
        self.apiKeyResolver = apiKeyResolver
    }

    public func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        do {
            // Resolve API key for the program's model config
            guard let apiKey = apiKeyResolver.resolveAPIKey(for: program.modelConfig.apiKeyName) else {
                throw RemoteAPIClient.ClientError.missingAPIKey
            }
            
            // Create client with program configuration
            let client = RemoteAPIClient(configuration: RemoteAPIClient.Configuration(
                modelConfig: program.modelConfig,
                systemPrompt: program.systemPrompt,
                apiKey: apiKey
            ))
            
            let response = try await client.submitTask(
                audioURL: metadata.audioURL,
                transcript: metadata.transcript,
                localeIdentifier: metadata.localeIdentifier,
                eventLog: context.eventLog,
                nodeSnapshot: context.nodeSnapshot
            )

            let transcript = response.transcript ?? metadata.transcript ?? ""
            guard !transcript.isEmpty else {
                AppLogger.ui().log(event: "pipeline:remote:emptyTranscript", data: ["programId": program.id])
                throw PipelineError.emptyTranscript
            }

            return OperationGenerationResult(transcript: transcript, operations: response.operations)
        } catch {
            AppLogger.ui().logError(event: "pipeline:remote:error", error: error, data: ["programId": program.id])
            throw error
        }
    }
}
