import SwiftUI
import TalkToDoShared

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
                        WelcomeStep(onStart: {
                            store.proceedToAPIKeySetup()
                        })

                    case .apiKeySetup:
                        APIKeySetupStep(
                            settingsStore: store.settingsStore,
                            onContinue: {
                                store.proceedToPermissionsExplanation()
                            },
                            onSkipToOnDevice: {
                                // User chose on-device mode
                                store.proceedToPermissionsExplanation()
                            }
                        )

                    case .permissionsExplanation:
                        PermissionsExplanationStep(onContinue: {
                            store.proceedToPermissionsRequest()
                            Task {
                                await store.requestPermissions()
                            }
                        })

                    case .requestingPermissions:
                        PermissionsRequestStep(
                            micStatus: store.micPermissionStatus,
                            speechStatus: store.speechPermissionStatus
                        )

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
                .foregroundStyle(Color.accentColor)

            Text("Welcome to TalkToDo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Speak naturally. Get structured lists.\n\nJust hold the mic and speak—your thoughts become organized to-do items powered by AI.")
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
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct APIKeySetupStep: View {
    @Bindable var settingsStore: VoiceProcessingSettingsStore
    let onContinue: () -> Void
    let onSkipToOnDevice: () -> Void

    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showOnDeviceDialog = false

    private var envAPIKey: String? {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEnvKey: Bool {
        if let key = envAPIKey, !key.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Connect to Gemini AI")
                .font(.title2)
                .fontWeight(.semibold)

            if hasEnvKey {
                // Environment key detected
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)

                    Text("API Key Found")
                        .font(.headline)

                    Text("Your Gemini API key was detected in the environment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 300)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 16)
            } else if case .present = settingsStore.geminiKeyStatus {
                // Key already stored
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)

                    Text("API Key Configured")
                        .font(.headline)

                    Text("Your Gemini API key is ready to use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 300)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 16)
            } else {
                // Need to paste key
                VStack(spacing: 12) {
                    Text("TalkToDo uses Google's Gemini to understand your voice and create structured lists.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: pasteAndValidate) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "doc.on.clipboard")
                            }
                            Text(isValidating ? "Validating..." : "Paste API Key")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 300)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isValidating)

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Example: AIzaSyC8_abc123...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Text("Get a free API key →")
                            .font(.footnote)
                    }
                    .padding(.top, 8)
                }

                Button(action: { showOnDeviceDialog = true }) {
                    Text("Skip - Use On-Device Mode")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.top, 8)
            }
        }
        .alert("Use On-Device Mode?", isPresented: $showOnDeviceDialog) {
            Button("Go Back", role: .cancel) {}
            Button("Continue") {
                // Switch to on-device mode
                settingsStore.update(mode: .onDevice)
                onSkipToOnDevice()
            }
        } message: {
            Text("On-device mode runs entirely offline but requires a 1.2GB model download that takes 5-10 minutes on first launch.")
        }
    }

    private func pasteAndValidate() {
        #if os(iOS)
        guard let clipboardText = UIPasteboard.general.string else {
            validationError = "Clipboard is empty"
            return
        }
        #else
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            validationError = "Clipboard is empty"
            return
        }
        #endif

        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "Clipboard is empty"
            return
        }

        // Basic format validation (Gemini keys start with "AIza")
        guard trimmed.hasPrefix("AIza") else {
            validationError = "Invalid key format. Gemini keys start with 'AIza'"
            return
        }

        isValidating = true
        validationError = nil

        // Store the key
        settingsStore.updateGeminiAPIKey(trimmed)

        // Simulate validation (in production, you'd make an API call)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            isValidating = false
            // For now, assume valid if format is correct
            onContinue()
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct PermissionsExplanationStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Two Quick Permissions")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone")
                            .font(.headline)
                        Text("So you can record your voice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech Recognition")
                            .font(.headline)
                        Text("To convert speech to text in real-time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onContinue) {
                Text("Grant Permissions")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct PermissionsRequestStep: View {
    let micStatus: OnboardingStore.PermissionStatus
    let speechStatus: OnboardingStore.PermissionStatus

    var body: some View {
        VStack(spacing: 24) {
            Text("Requesting Permissions")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                PermissionRow(
                    title: "Microphone Access",
                    status: micStatus
                )

                PermissionRow(
                    title: "Speech Recognition",
                    status: speechStatus
                )
            }
            .padding()
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct PermissionRow: View {
    let title: String
    let status: OnboardingStore.PermissionStatus

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .font(.title2)
                .frame(width: 40)

            Text(title)
                .font(.body)

            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "square")
                .foregroundStyle(.secondary)
        case .requesting:
            ProgressView()
                .scaleEffect(0.8)
        case .granted:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.square.fill")
                .foregroundStyle(.red)
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

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Hold the microphone button and speak naturally. TalkToDo will organize your thoughts into lists.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                    Text("Try saying: \"Add buy groceries with milk, bread, and eggs as sub-items\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onContinue) {
                Text("Start Using TalkToDo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.accentColor)
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
    let settingsStore = VoiceProcessingSettingsStore()
    let store = OnboardingStore(
        voiceInputStore: VoiceInputStore(),
        settingsStore: settingsStore
    )
    return OnboardingView(store: store, onComplete: {})
}

#Preview("API Key") {
    let settingsStore = VoiceProcessingSettingsStore()
    let store = OnboardingStore(
        voiceInputStore: VoiceInputStore(),
        settingsStore: settingsStore
    )
    store.state = .inProgress(step: .apiKeySetup)
    return OnboardingView(store: store, onComplete: {})
}
