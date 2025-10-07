public struct AnyVoiceProcessingPipeline: VoiceProcessingPipeline {
    private let processHandler: @Sendable (RecordingMetadata, NodeContext?) async throws -> OperationGenerationResult

    public init<P: VoiceProcessingPipeline>(_ pipeline: P) {
        self.processHandler = { metadata, nodeContext in
            try await pipeline.process(metadata: metadata, nodeContext: nodeContext)
        }
    }

    public func process(
        metadata: RecordingMetadata,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        try await processHandler(metadata, nodeContext)
    }
}
