import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct OnboardingView: View {
    @Bindable var store: OnboardingStore
    let onComplete: () -> Void

    public init(store: OnboardingStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            #if os(iOS)
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #else
            Color(.windowBackgroundColor)
                .ignoresSafeArea()
            #endif

            VStack(spacing: 32) {
                switch store.state {
                case .notStarted:
                    WelcomeStep(onStart: {
                        Task {
                            await store.startOnboarding()
                        }
                    })

                case .inProgress(let step):
                    switch step {
                    case .welcome:
                        WelcomeStep(onStart: {})

                    case .downloadingModel:
                        DownloadingStep(progress: store.downloadProgress)

                    case .requestingPermissions:
                        PermissionsStep()

                    case .complete:
                        CompletedStep(onContinue: onComplete)
                    }

                case .completed:
                    CompletedStep(onContinue: onComplete)

                case .failed(let message):
                    FailedStep(message: message, onRetry: {
                        Task {
                            await store.startOnboarding()
                        }
                    })
                }
            }
            .padding(40)
        }
    }
}

// MARK: - Steps

@available(iOS 18.0, macOS 15.0, *)
private struct WelcomeStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Welcome to TalkToDo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Transform your voice into structured lists with the power of on-device AI")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onStart) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct DownloadingStep: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Text("Downloading AI Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This will take a few minutes. The model runs entirely on your device for privacy.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct PermissionsStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Requesting Permissions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("TalkToDo needs access to your microphone and speech recognition to capture your voice.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ProgressView()
                .padding(.top)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct CompletedStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("You're ready to start creating structured lists with your voice.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct FailedStep: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Setup Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
        }
    }
}

#Preview("Welcome") {
    let store = OnboardingStore(
        voiceInputStore: VoiceInputStore(),
        llmService: LLMInferenceService()
    )
    return OnboardingView(store: store, onComplete: {})
}

#Preview("Downloading") {
    let store = OnboardingStore(
        voiceInputStore: VoiceInputStore(),
        llmService: LLMInferenceService()
    )
    store.state = .inProgress(step: .downloadingModel)
    store.downloadProgress = 0.65
    return OnboardingView(store: store, onComplete: {})
}
