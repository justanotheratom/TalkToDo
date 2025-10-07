import Foundation
import TalkToDoShared

public struct GeminiTextPipeline: TextProcessingPipeline {
    private let client: any GeminiClientProtocol
    private let fallback: AnyTextProcessingPipeline

    public init(client: any GeminiClientProtocol, fallback: AnyTextProcessingPipeline) {
        self.client = client
        self.fallback = fallback
    }

    public func process(
        text: String,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.ui().log(event: "textPipeline:gemini:empty", data: [:])
            return try await fallback.process(text: text, nodeContext: nodeContext)
        }

        do {
            let response = try await client.submitTask(
                audioURL: nil,
                transcript: trimmed,
                localeIdentifier: Locale.current.identifier
            )

            let transcript = response.transcript ?? trimmed
            AppLogger.ui().log(event: "textPipeline:gemini:success", data: [
                "operationCount": response.operations.count
            ])

            return OperationGenerationResult(
                transcript: transcript,
                operations: response.operations
            )
        } catch {
            AppLogger.ui().logError(event: "textPipeline:gemini:error", error: error)
            return try await fallback.process(text: text, nodeContext: nodeContext)
        }
    }
}
