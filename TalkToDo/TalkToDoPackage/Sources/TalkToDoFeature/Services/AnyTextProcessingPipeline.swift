public struct AnyTextProcessingPipeline: TextProcessingPipeline {
    private let processHandler: @Sendable (String, NodeContext?) async throws -> OperationGenerationResult

    public init<P: TextProcessingPipeline>(_ pipeline: P) {
        self.processHandler = { text, nodeContext in
            try await pipeline.process(text: text, nodeContext: nodeContext)
        }
    }

    public func process(
        text: String,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        try await processHandler(text, nodeContext)
    }
}
