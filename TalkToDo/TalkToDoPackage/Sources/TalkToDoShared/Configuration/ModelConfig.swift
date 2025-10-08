import Foundation

public enum ModelProvider: String, CaseIterable, Sendable {
    case gemini = "gemini"
    case openai = "openai"
    case anthropic = "anthropic"
    
    public var displayName: String {
        switch self {
        case .gemini:
            return "Google Gemini"
        case .openai:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        }
    }
}

public struct ModelConfig: Sendable, Identifiable, Equatable {
    public let id: String
    public let provider: ModelProvider
    public let displayName: String
    public let modelIdentifier: String
    public let apiKeyName: String
    public let baseURL: URL
    public let supportsAudio: Bool
    public let supportsText: Bool
    
    public init(
        id: String,
        provider: ModelProvider,
        displayName: String,
        modelIdentifier: String,
        apiKeyName: String,
        baseURL: URL,
        supportsAudio: Bool,
        supportsText: Bool
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.modelIdentifier = modelIdentifier
        self.apiKeyName = apiKeyName
        self.baseURL = baseURL
        self.supportsAudio = supportsAudio
        self.supportsText = supportsText
    }
}

public protocol APIKeyResolver: Sendable {
    func resolveAPIKey(for keyName: String) -> String?
}

public final class ModelConfigCatalog: @unchecked Sendable {
    public static let shared = ModelConfigCatalog()
    
    private let keychainService: KeychainService
    
    public init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
    }
    
    public let allConfigs: [ModelConfig] = [
        // Gemini configs
        ModelConfig(
            id: "gemini-flash-lite",
            provider: .gemini,
            displayName: "Gemini 2.5 Flash Lite",
            modelIdentifier: "gemini-2.5-flash-lite",
            apiKeyName: "GEMINI_API_KEY",
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!,
            supportsAudio: true,
            supportsText: true
        ),
        ModelConfig(
            id: "gemini-flash",
            provider: .gemini,
            displayName: "Gemini 2.0 Flash",
            modelIdentifier: "gemini-2.0-flash",
            apiKeyName: "GEMINI_API_KEY",
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!,
            supportsAudio: true,
            supportsText: true
        ),
        // OpenAI configs
        ModelConfig(
            id: "openai-gpt4o",
            provider: .openai,
            displayName: "GPT-4o",
            modelIdentifier: "gpt-4o",
            apiKeyName: "OPENAI_API_KEY",
            baseURL: URL(string: "https://api.openai.com/v1/")!,
            supportsAudio: false,
            supportsText: true
        ),
        ModelConfig(
            id: "openai-gpt4o-audio",
            provider: .openai,
            displayName: "GPT-4o (Audio)",
            modelIdentifier: "gpt-4o",
            apiKeyName: "OPENAI_API_KEY",
            baseURL: URL(string: "https://api.openai.com/v1/")!,
            supportsAudio: true,
            supportsText: true
        )
    ]
    
    public var voiceCapableConfigs: [ModelConfig] {
        allConfigs.filter { $0.supportsAudio }
    }
    
    public var textCapableConfigs: [ModelConfig] {
        allConfigs.filter { $0.supportsText }
    }
    
    public func config(for id: String) -> ModelConfig? {
        allConfigs.first { $0.id == id }
    }
}

public final class DefaultAPIKeyResolver: APIKeyResolver, @unchecked Sendable {
    private let keychainService: KeychainService
    
    public init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
    }
    
    public func resolveAPIKey(for keyName: String) -> String? {
        // First check environment variables
        if let envKey = ProcessInfo.processInfo.environment[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        
        // Then check keychain
        do {
            return try keychainService.read(key: keyName)
        } catch {
            return nil
        }
    }
}
