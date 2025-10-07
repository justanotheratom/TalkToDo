import Foundation
import TalkToDoShared

@MainActor
public final class VoiceProcessingPipelineFactory {
    private let settingsStore: VoiceProcessingSettingsStore
    private let llmService: LLMInferenceService
    private let apiKeyProvider: () -> String?
    private lazy var onDevicePipeline = OnDeviceVoicePipeline(llmService: llmService)
    private var cachedGeminiPipeline: GeminiVoicePipeline?
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
            return AnyVoiceProcessingPipeline(onDevicePipeline)
        case .remoteGemini:
            guard let pipeline = geminiPipeline() else {
                return AnyVoiceProcessingPipeline(onDevicePipeline)
            }
            return AnyVoiceProcessingPipeline(pipeline)
        }
    }

    public func currentPipeline() -> AnyVoiceProcessingPipeline {
        pipeline(for: settingsStore.mode)
    }

    private func geminiPipeline() -> GeminiVoicePipeline? {
        let keyFromStore = settingsStore.remoteAPIKey
        let resolvedKey = keyFromStore?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (resolvedKey?.isEmpty == false ? resolvedKey : apiKeyProvider()) ?? ""

        guard !apiKey.isEmpty else {
            AppLogger.ui().log(event: "pipeline:factory:missingGeminiKey", data: [:])
            cachedGeminiPipeline = nil
            cachedGeminiAPIKey = nil
            return nil
        }

        if let cached = cachedGeminiPipeline, cachedGeminiAPIKey == apiKey {
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
            fallback: AnyVoiceProcessingPipeline(onDevicePipeline)
        )
        cachedGeminiPipeline = pipeline
        cachedGeminiAPIKey = apiKey
        return pipeline
    }
}
