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
public final class VoiceProcessingSettingsStore {
    private enum DefaultsKey {
        static let mode = "voiceProcessingMode"
    }

    private let defaults: UserDefaults

    public private(set) var mode: ProcessingMode

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.string(forKey: DefaultsKey.mode),
           let parsed = ProcessingMode(rawValue: stored) {
            mode = parsed
        } else {
            mode = .onDevice
        }
    }

    public func update(mode: ProcessingMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.mode)
    }
}
