import Foundation
import TalkToDoShared

private enum RemotePipelineError: Error, LocalizedError {
    case missingGeminiAPIKey
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingGeminiAPIKey:
            return "Add a Gemini API key in Settings to use remote processing."
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
    private let settingsStore: VoiceProcessingSettingsStore
    private let llmService: LLMInferenceService
    private let apiKeyProvider: () -> String?
    private lazy var onDeviceVoicePipeline = OnDeviceVoicePipeline(llmService: llmService)
    private lazy var onDeviceTextPipeline = OnDeviceTextPipeline(llmService: llmService)
    private var cachedGeminiVoicePipeline: GeminiVoicePipeline?
    private var cachedGeminiTextPipeline: GeminiTextPipeline?
    private var cachedGeminiClient: GeminiAPIClient?
    private var cachedGeminiAPIKey: String?

    public init(
        settingsStore: VoiceProcessingSettingsStore,
        llmService: LLMInferenceService,
        apiKeyProvider: @escaping () -> String? = { ProcessInfo.processInfo.environment["GEMINI_API_KEY"] }
    ) {
        self.settingsStore = settingsStore
        self.llmService = llmService
        self.apiKeyProvider = apiKeyProvider
    }

    public func pipeline(for mode: ProcessingMode) -> AnyVoiceProcessingPipeline {
        switch mode {
        case .onDevice:
            return AnyVoiceProcessingPipeline(onDeviceVoicePipeline)
        case .remoteGemini:
            switch geminiPipeline() {
            case .success(let pipeline):
                return AnyVoiceProcessingPipeline(pipeline)
            case .failure(let error):
                return AnyVoiceProcessingPipeline(MissingRemoteVoicePipeline(error: error))
            }
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
            switch geminiTextPipeline() {
            case .success(let pipeline):
                return AnyTextProcessingPipeline(pipeline)
            case .failure(let error):
                return AnyTextProcessingPipeline(MissingRemoteTextPipeline(error: error))
            }
        }
    }

    public func currentTextPipeline() -> AnyTextProcessingPipeline {
        textPipeline(for: settingsStore.mode)
    }

    private func geminiPipeline() -> Result<GeminiVoicePipeline, RemotePipelineError> {
        switch geminiClient() {
        case .failure(let error):
            return .failure(error)
        case .success(let client):
            if let cached = cachedGeminiVoicePipeline {
                return .success(cached)
            }

            let pipeline = GeminiVoicePipeline(client: client)
            cachedGeminiVoicePipeline = pipeline
            return .success(pipeline)
        }
    }

    private func geminiTextPipeline() -> Result<GeminiTextPipeline, RemotePipelineError> {
        switch geminiClient() {
        case .failure(let error):
            return .failure(error)
        case .success(let client):
            if let cached = cachedGeminiTextPipeline {
                return .success(cached)
            }

            let pipeline = GeminiTextPipeline(client: client)
            cachedGeminiTextPipeline = pipeline
            return .success(pipeline)
        }
    }

    private func geminiClient() -> Result<GeminiAPIClient, RemotePipelineError> {
        let keyFromStore = settingsStore.remoteAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = keyFromStore?.isEmpty == false ? keyFromStore : environmentKey

        guard let apiKey = resolvedKey, !apiKey.isEmpty else {
            AppLogger.ui().log(event: "pipeline:factory:missingGeminiKey", data: [:])
            invalidateGeminiCaches()
            return .failure(.missingGeminiAPIKey)
        }

        if let cachedKey = cachedGeminiAPIKey,
           let cachedClient = cachedGeminiClient,
           cachedKey == apiKey {
            return .success(cachedClient)
        }

        guard let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/") else {
            AppLogger.ui().log(event: "pipeline:factory:invalidGeminiURL", data: [:])
            invalidateGeminiCaches()
            return .failure(.invalidConfiguration)
        }

        let configuration = GeminiAPIClient.Configuration(baseURL: baseURL, apiKey: apiKey)
        let client = GeminiAPIClient(configuration: configuration)
        cachedGeminiAPIKey = apiKey
        cachedGeminiClient = client
        cachedGeminiVoicePipeline = nil
        cachedGeminiTextPipeline = nil
        return .success(client)
    }

    private func invalidateGeminiCaches() {
        cachedGeminiVoicePipeline = nil
        cachedGeminiTextPipeline = nil
        cachedGeminiClient = nil
        cachedGeminiAPIKey = nil
    }
}
