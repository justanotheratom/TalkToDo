import Foundation
import TalkToDoShared

private enum RemotePipelineError: Error, LocalizedError {
    case missingAPIKey(programId: String)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let programId):
            return "Add an API key for the selected program (\(programId)) in Settings to use remote processing."
        case .invalidConfiguration:
            return "Remote processing is misconfigured. Please contact support."
        }
    }
}

private struct MissingRemoteVoicePipeline: VoiceProcessingPipeline, Sendable {
    let error: RemotePipelineError

    func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        throw error
    }
}

private struct MissingRemoteTextPipeline: TextProcessingPipeline, Sendable {
    let error: RemotePipelineError

    func process(
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        throw error
    }
}

@MainActor
public final class VoiceProcessingPipelineFactory {
    private let settingsStore: ProcessingSettingsStore
    private let llmService: LLMInferenceService
    private let apiKeyResolver: APIKeyResolver
    private lazy var onDeviceVoicePipeline = OnDeviceVoicePipeline(llmService: llmService)
    private lazy var onDeviceTextPipeline = OnDeviceTextPipeline(llmService: llmService)
    private var cachedPipelines: [String: AnyVoiceProcessingPipeline] = [:]
    private var cachedTextPipelines: [String: AnyTextProcessingPipeline] = [:]

    public init(
        settingsStore: ProcessingSettingsStore,
        llmService: LLMInferenceService,
        apiKeyResolver: APIKeyResolver = DefaultAPIKeyResolver()
    ) {
        self.settingsStore = settingsStore
        self.llmService = llmService
        self.apiKeyResolver = apiKeyResolver
    }

    public func pipeline(for mode: ProcessingMode) -> AnyVoiceProcessingPipeline {
        switch mode {
        case .onDevice:
            return AnyVoiceProcessingPipeline(onDeviceVoicePipeline)
        case .remoteGemini:
            let program = settingsStore.resolvedVoiceProgram()
            return voicePipeline(for: program)
        }
    }

    public func currentPipeline() -> AnyVoiceProcessingPipeline {
        pipeline(for: settingsStore.mode)
    }

    public func textPipeline(for mode: ProcessingMode) -> AnyTextProcessingPipeline {
        switch mode {
        case .onDevice:
            return AnyTextProcessingPipeline(onDeviceTextPipeline)
        case .remoteGemini:
            let program = settingsStore.resolvedTextProgram()
            return textPipeline(for: program)
        }
    }

    public func currentTextPipeline() -> AnyTextProcessingPipeline {
        textPipeline(for: settingsStore.mode)
    }

    public func voicePipeline(for program: any AIProgram) -> AnyVoiceProcessingPipeline {
        let programId = program.id
        
        // Check cache first
        if let cached = cachedPipelines[programId] {
            return cached
        }
        
        // Check if API key is available
        guard apiKeyResolver.resolveAPIKey(for: program.modelConfig.apiKeyName) != nil else {
            let error = RemotePipelineError.missingAPIKey(programId: programId)
            return AnyVoiceProcessingPipeline(MissingRemoteVoicePipeline(error: error))
        }
        
        // Create new pipeline
        let pipeline = RemoteVoicePipeline(program: program, apiKeyResolver: apiKeyResolver)
        let wrappedPipeline = AnyVoiceProcessingPipeline(pipeline)
        cachedPipelines[programId] = wrappedPipeline
        return wrappedPipeline
    }

    public func textPipeline(for program: any AIProgram) -> AnyTextProcessingPipeline {
        let programId = program.id
        
        // Check cache first
        if let cached = cachedTextPipelines[programId] {
            return cached
        }
        
        // Check if API key is available
        guard apiKeyResolver.resolveAPIKey(for: program.modelConfig.apiKeyName) != nil else {
            let error = RemotePipelineError.missingAPIKey(programId: programId)
            return AnyTextProcessingPipeline(MissingRemoteTextPipeline(error: error))
        }
        
        // Create new pipeline
        let pipeline = RemoteTextPipeline(program: program, apiKeyResolver: apiKeyResolver)
        let wrappedPipeline = AnyTextProcessingPipeline(pipeline)
        cachedTextPipelines[programId] = wrappedPipeline
        return wrappedPipeline
    }

    public func invalidateCaches() {
        cachedPipelines.removeAll()
        cachedTextPipelines.removeAll()
    }
}
