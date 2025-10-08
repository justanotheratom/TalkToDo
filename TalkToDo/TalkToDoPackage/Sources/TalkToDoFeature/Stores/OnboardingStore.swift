import Foundation
import Observation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class OnboardingStore {
    public enum OnboardingStep: Equatable {
        case welcome
        case apiKeySetup
        case permissionsExplanation
        case requestingPermissions
        case complete
    }

    public enum OnboardingState: Equatable {
        case notStarted
        case inProgress(step: OnboardingStep)
        case completed
        case failed(message: String)
    }

    public enum PermissionStatus: Equatable {
        case pending
        case requesting
        case granted
        case denied
    }

    public var state: OnboardingState = .notStarted
    public var micPermissionStatus: PermissionStatus = .pending
    public var speechPermissionStatus: PermissionStatus = .pending
    public var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    @ObservationIgnored private let voiceInputStore: VoiceInputStore
    @ObservationIgnored internal let settingsStore: VoiceProcessingSettingsStore

    public init(voiceInputStore: VoiceInputStore, settingsStore: VoiceProcessingSettingsStore) {
        self.voiceInputStore = voiceInputStore
        self.settingsStore = settingsStore
    }

    // MARK: - Onboarding Flow

    public func startOnboarding() async {
        state = .inProgress(step: .welcome)
        AppLogger.ui().log(event: "onboarding:started", data: [:])
    }

    public func proceedToAPIKeySetup() {
        state = .inProgress(step: .apiKeySetup)
    }

    public func proceedToPermissionsExplanation() {
        state = .inProgress(step: .permissionsExplanation)
    }

    public func proceedToPermissionsRequest() {
        state = .inProgress(step: .requestingPermissions)
    }

    public func requestPermissions() async {
        // Use voiceInputStore's permission fetching
        await voiceInputStore.prefetchPermissions()

        // Update our status based on voiceInputStore state
        speechPermissionStatus = voiceInputStore.speechPermissionState == .granted ? .granted : .denied

        #if os(iOS)
        micPermissionStatus = voiceInputStore.microphonePermissionState == .granted ? .granted : .denied
        #else
        micPermissionStatus = .granted
        #endif

        // Check if both permissions were granted
        if speechPermissionStatus == .denied || micPermissionStatus == .denied {
            state = .failed(message: "Microphone and speech recognition permissions are required.")
            AppLogger.ui().log(event: "onboarding:permissionsDenied", data: [
                "speech": String(describing: speechPermissionStatus),
                "microphone": String(describing: micPermissionStatus)
            ])
        } else {
            AppLogger.ui().log(event: "onboarding:permissionsGranted", data: [:])
            completeOnboarding()
        }
    }

    public func completeOnboarding() {
        state = .completed
        hasCompletedOnboarding = true
        AppLogger.ui().log(event: "onboarding:completed", data: [:])
    }

    public func skipOnboarding() {
        hasCompletedOnboarding = true
        state = .completed
    }
}
