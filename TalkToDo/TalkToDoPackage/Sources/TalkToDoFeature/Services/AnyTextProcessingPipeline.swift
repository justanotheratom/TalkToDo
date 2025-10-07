public struct AnyTextProcessingPipeline: TextProcessingPipeline {
    private let processHandler: @Sendable (String, ProcessingContext) async throws -> OperationGenerationResult

    public init<P: TextProcessingPipeline>(_ pipeline: P) {
        self.processHandler = { text, context in
            try await pipeline.process(text: text, context: context)
        }
    }

    public func process(
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        try await processHandler(text, context)
    }
}
