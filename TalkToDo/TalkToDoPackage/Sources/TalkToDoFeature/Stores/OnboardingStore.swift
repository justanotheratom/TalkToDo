import Foundation
import Observation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class OnboardingStore {
    public enum OnboardingStep: Equatable {
        case welcome
        case downloadingModel
        case requestingPermissions
        case complete
    }

    public enum OnboardingState: Equatable {
        case notStarted
        case inProgress(step: OnboardingStep)
        case completed
        case failed(message: String)
    }

    public var state: OnboardingState = .notStarted
    public var downloadProgress: Double = 0.0
    public var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    @ObservationIgnored private let storage = ModelStorageService()
    @ObservationIgnored private let downloadService = ModelDownloadService()
    @ObservationIgnored private let voiceInputStore: VoiceInputStore
    @ObservationIgnored private let llmService: LLMInferenceService

    public init(voiceInputStore: VoiceInputStore, llmService: LLMInferenceService) {
        self.voiceInputStore = voiceInputStore
        self.llmService = llmService
    }

    // MARK: - Onboarding Flow

    public func startOnboarding() async {
        state = .inProgress(step: .welcome)

        // Wait briefly for user to see welcome
        try? await Task.sleep(for: .seconds(1))

        // Download default model if needed
        let defaultModel = ModelCatalog.defaultModel
        if !storage.isDownloaded(entry: defaultModel) {
            await downloadDefaultModel(defaultModel)
        }

        // Request permissions
        await requestPermissions()

        // Load model
        await loadModel(defaultModel)

        // Mark as complete
        state = .completed
        hasCompletedOnboarding = true

        AppLogger.ui().log(event: "onboarding:completed", data: [:])
    }

    private func downloadDefaultModel(_ model: ModelCatalogEntry) async {
        state = .inProgress(step: .downloadingModel)
        downloadProgress = 0.0

        do {
            let result = try await downloadService.downloadModel(entry: model) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress
                }
            }

            AppLogger.ui().log(event: "onboarding:modelDownloaded", data: [
                "modelSlug": model.slug,
                "path": result.localURL.path
            ])
        } catch {
            state = .failed(message: "Failed to download model: \(error.localizedDescription)")
            AppLogger.ui().logError(event: "onboarding:downloadFailed", error: error)
        }
    }

    private func requestPermissions() async {
        state = .inProgress(step: .requestingPermissions)
        await voiceInputStore.prefetchPermissions()

        if voiceInputStore.speechPermissionState == .denied ||
           voiceInputStore.microphonePermissionState == .denied {
            state = .failed(message: "Microphone and speech recognition permissions are required.")
            AppLogger.ui().log(event: "onboarding:permissionsDenied", data: [:])
        } else {
            AppLogger.ui().log(event: "onboarding:permissionsGranted", data: [:])
        }
    }

    private func loadModel(_ model: ModelCatalogEntry) async {
        do {
            let url = try storage.expectedResourceURL(for: model)
            try await llmService.loadModel(at: url)

            AppLogger.ui().log(event: "onboarding:modelLoaded", data: [
                "modelSlug": model.slug
            ])
        } catch {
            state = .failed(message: "Failed to load model: \(error.localizedDescription)")
            AppLogger.ui().logError(event: "onboarding:loadFailed", error: error)
        }
    }

    public func skipOnboarding() {
        hasCompletedOnboarding = true
        state = .completed
    }
}
