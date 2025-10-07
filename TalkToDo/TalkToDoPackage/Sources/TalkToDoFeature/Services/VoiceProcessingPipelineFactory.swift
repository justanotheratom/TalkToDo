import Foundation
import TalkToDoShared

@MainActor
public final class VoiceProcessingPipelineFactory {
    private let settingsStore: VoiceProcessingSettingsStore
    private let llmService: LLMInferenceService
    private let apiKeyProvider: () -> String?
    private lazy var onDeviceVoicePipeline = OnDeviceVoicePipeline(llmService: llmService)
    private lazy var onDeviceTextPipeline = OnDeviceTextPipeline(llmService: llmService)
    private var cachedGeminiVoicePipeline: GeminiVoicePipeline?
    private var cachedGeminiTextPipeline: GeminiTextPipeline?
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
            guard let pipeline = geminiPipeline() else {
                return AnyVoiceProcessingPipeline(onDeviceVoicePipeline)
            }
            return AnyVoiceProcessingPipeline(pipeline)
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
            guard let pipeline = geminiTextPipeline() else {
                return AnyTextProcessingPipeline(onDeviceTextPipeline)
            }
            return AnyTextProcessingPipeline(pipeline)
        }
    }

    public func currentTextPipeline() -> AnyTextProcessingPipeline {
        textPipeline(for: settingsStore.mode)
    }

    private func geminiPipeline() -> GeminiVoicePipeline? {
        let keyFromStore = settingsStore.remoteAPIKey
        let resolvedKey = keyFromStore?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (resolvedKey?.isEmpty == false ? resolvedKey : apiKeyProvider()) ?? ""

        guard !apiKey.isEmpty else {
            AppLogger.ui().log(event: "pipeline:factory:missingGeminiKey", data: [:])
            cachedGeminiVoicePipeline = nil
            cachedGeminiTextPipeline = nil
            cachedGeminiAPIKey = nil
            return nil
        }

        if let cached = cachedGeminiVoicePipeline, cachedGeminiAPIKey == apiKey {
            return cached
        }

        guard let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/") else {
            AppLogger.ui().log(event: "pipeline:factory:invalidGeminiURL", data: [:])
            return nil
        }

        let configuration = GeminiAPIClient.Configuration(baseURL: baseURL, apiKey: apiKey)
        let client = GeminiAPIClient(configuration: configuration)
        let pipeline = GeminiVoicePipeline(
            client: client,
            fallback: AnyVoiceProcessingPipeline(onDeviceVoicePipeline)
        )
        cachedGeminiVoicePipeline = pipeline
        cachedGeminiAPIKey = apiKey
        return pipeline
    }

    private func geminiTextPipeline() -> GeminiTextPipeline? {
        guard let apiKey = cachedGeminiAPIKey,
              cachedGeminiVoicePipeline != nil else {
            // Ensure voice pipeline is initialized so key is cached
            guard let _ = geminiPipeline() else { return nil }
            return cachedGeminiTextPipeline
        }

        if let cached = cachedGeminiTextPipeline {
            return cached
        }

        guard let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/") else {
            return nil
        }

        let configuration = GeminiAPIClient.Configuration(baseURL: baseURL, apiKey: apiKey)
        let client = GeminiAPIClient(configuration: configuration)
        let pipeline = GeminiTextPipeline(
            client: client,
            fallback: AnyTextProcessingPipeline(onDeviceTextPipeline)
        )
        cachedGeminiTextPipeline = pipeline
        return pipeline
    }
}
