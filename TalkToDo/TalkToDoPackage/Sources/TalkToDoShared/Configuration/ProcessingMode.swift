import Foundation
import Observation

public enum ProcessingMode: String, CaseIterable, Sendable {
    case onDevice
    case remoteGemini

    public var displayName: String {
        switch self {
        case .onDevice:
            return "On-Device"
        case .remoteGemini:
            return "Remote (Gemini)"
        }
    }

    public var description: String {
        switch self {
        case .onDevice:
            return "Runs transcription and inference entirely on this device."
        case .remoteGemini:
            return "Uploads audio to Gemini 2.5 Flash Lite for processing."
        }
    }

    public var warningCopy: String? {
        switch self {
        case .onDevice:
            return nil
        case .remoteGemini:
            return "Remote mode may be slower and sends audio off-device."
        }
    }
}

@MainActor
@Observable
public final class ProcessingSettingsStore {
    private enum DefaultsKey {
        static let mode = "voiceProcessingMode"
        static let selectedVoiceProgramId = "selectedVoiceProgramId"
        static let selectedTextProgramId = "selectedTextProgramId"
        // Legacy key for migration
        static let geminiAPIKey = "geminiAPIKey"
    }

    private let defaults: UserDefaults
    private let keychainService: KeychainService
    private let apiKeyResolver: APIKeyResolver

    public private(set) var mode: ProcessingMode
    public private(set) var selectedVoiceProgramId: String?
    public private(set) var selectedTextProgramId: String?

    public init(
        defaults: UserDefaults = .standard,
        keychainService: KeychainService = KeychainService(),
        apiKeyResolver: APIKeyResolver = DefaultAPIKeyResolver()
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
        self.apiKeyResolver = apiKeyResolver

        if let stored = defaults.string(forKey: DefaultsKey.mode),
           let parsed = ProcessingMode(rawValue: stored) {
            mode = parsed
        } else {
            mode = .remoteGemini
        }

        selectedVoiceProgramId = defaults.string(forKey: DefaultsKey.selectedVoiceProgramId)
        selectedTextProgramId = defaults.string(forKey: DefaultsKey.selectedTextProgramId)
        
        // Migrate existing Gemini key from UserDefaults to keychain
        migrateLegacyGeminiKey()
    }

    public func update(mode: ProcessingMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.mode)
    }

    public func updateSelectedVoiceProgram(id: String?) {
        selectedVoiceProgramId = id
        if let id = id {
            defaults.set(id, forKey: DefaultsKey.selectedVoiceProgramId)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedVoiceProgramId)
        }
    }

    public func updateSelectedTextProgram(id: String?) {
        selectedTextProgramId = id
        if let id = id {
            defaults.set(id, forKey: DefaultsKey.selectedTextProgramId)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedTextProgramId)
        }
    }

    public func resolvedVoiceProgram() -> any AIProgram {
        // This will be implemented in the Feature module
        fatalError("resolvedVoiceProgram() must be implemented in the Feature module")
    }
    
    public func resolvedTextProgram() -> any AIProgram {
        // This will be implemented in the Feature module
        fatalError("resolvedTextProgram() must be implemented in the Feature module")
    }

    public func storeAPIKey(for keyName: String, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try keychainService.save(key: keyName, value: trimmed)
    }

    public func deleteAPIKey(for keyName: String) throws {
        try keychainService.delete(key: keyName)
    }

    public func resolveAPIKey(for keyName: String) -> String? {
        apiKeyResolver.resolveAPIKey(for: keyName)
    }

    public func apiKeyStatus(for keyName: String) -> GeminiKeyStatus {
        guard let key = resolveAPIKey(for: keyName), !key.isEmpty else {
            return .missing
        }
        let masked = String(repeating: "•", count: max(4, key.count - 4)) + key.suffix(4)
        return .present(masked: masked)
    }

    private func migrateLegacyGeminiKey() {
        // Check if we have a legacy Gemini key in UserDefaults
        if let legacyKey = defaults.string(forKey: DefaultsKey.geminiAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyKey.isEmpty {
            do {
                // Migrate to keychain
                try keychainService.save(key: "GEMINI_API_KEY", value: legacyKey)
                // Remove from UserDefaults
                defaults.removeObject(forKey: DefaultsKey.geminiAPIKey)
            } catch {
                // If keychain save fails, keep the key in UserDefaults for now
                AppLogger.ui().logError(event: "settings:migration:keychainFailed", error: error)
            }
        }
    }
}
