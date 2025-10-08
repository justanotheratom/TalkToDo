import Foundation
import TalkToDoShared

public struct RemoteTextPipeline: TextProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyText

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Please enter some text to convert into tasks."
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
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.ui().log(event: "textPipeline:remote:empty", data: ["programId": program.id])
            throw PipelineError.emptyText
        }

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
                audioURL: nil,
                transcript: trimmed,
                localeIdentifier: Locale.current.identifier,
                eventLog: context.eventLog,
                nodeSnapshot: context.nodeSnapshot
            )

            let transcript = response.transcript ?? trimmed
            AppLogger.ui().log(event: "textPipeline:remote:success", data: [
                "operationCount": response.operations.count,
                "programId": program.id
            ])

            return OperationGenerationResult(
                transcript: transcript,
                operations: response.operations
            )
        } catch {
            AppLogger.ui().logError(event: "textPipeline:remote:error", error: error, data: ["programId": program.id])
            throw error
        }
    }
}
