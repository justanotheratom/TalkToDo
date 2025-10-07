public struct AnyVoiceProcessingPipeline: VoiceProcessingPipeline {
    private let processHandler: @Sendable (RecordingMetadata, ProcessingContext) async throws -> OperationGenerationResult

    public init<P: VoiceProcessingPipeline>(_ pipeline: P) {
        self.processHandler = { metadata, context in
            try await pipeline.process(metadata: metadata, context: context)
        }
    }

    public func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        try await processHandler(metadata, context)
    }
}
