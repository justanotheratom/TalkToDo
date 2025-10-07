import Foundation
import TalkToDoShared

public struct GeminiTextPipeline: TextProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyText

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Please enter some text to convert into tasks."
            }
        }
    }

    private let client: any GeminiClientProtocol

    public init(client: any GeminiClientProtocol) {
        self.client = client
    }

    public func process(
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.ui().log(event: "textPipeline:gemini:empty", data: [:])
            throw PipelineError.emptyText
        }

        do {
            let response = try await client.submitTask(
                audioURL: nil,
                transcript: trimmed,
                localeIdentifier: Locale.current.identifier,
                eventLog: context.eventLog,
                nodeSnapshot: context.nodeSnapshot
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
            throw error
        }
    }
}
