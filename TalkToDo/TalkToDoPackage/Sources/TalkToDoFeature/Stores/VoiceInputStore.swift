import Foundation
import Observation
import TalkToDoShared

#if os(iOS)
import AVFoundation
#endif

/// Store managing voice input UI state
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class VoiceInputStore {
    public enum Status: Equatable {
        case idle
        case recording
        case transcribing
        case disabled(message: String)
        case error(message: String)
    }

    public enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    // MARK: - Published State

    public var isRecording = false
    public var isTranscribing = false
    public var speechPermissionState: PermissionState = .unknown
    public var microphonePermissionState: PermissionState = .unknown
    public var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let speechService: SpeechRecognitionService
    @ObservationIgnored private var recordingStartTime: Date?
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService
    }

    deinit {
        errorDismissTask?.cancel()
    }

    // MARK: - Computed Properties

    public var status: Status {
        if let message = errorMessage {
            return .error(message: message)
        }
        if isTranscribing {
            return .transcribing
        }
        if isRecording {
            return .recording
        }
        if microphonePermissionState == .denied {
            return .disabled(message: "Enable microphone access in Settings")
        }
        if speechPermissionState == .denied {
            return .disabled(message: "Enable speech recognition in Settings")
        }
        return .idle
    }

    public var isEnabled: Bool {
        !isRecording && !isTranscribing &&
        speechPermissionState != .denied &&
        microphonePermissionState != .denied
    }

    // MARK: - Permissions

    public func prefetchPermissions() async {
        // Check speech recognition permission
        let speechStatus = await speechService.authorizationStatus()
        updateSpeechPermission(with: speechStatus)

        if speechStatus == .notDetermined {
            let requested = await speechService.requestAuthorization()
            updateSpeechPermission(with: requested)
        }

        // Check microphone permission on iOS
        #if os(iOS)
        await requestMicrophonePermission()
        #else
        microphonePermissionState = .granted
        #endif

        AppLogger.speech().log(event: "voice:permissionsPrefetched", data: [
            "speech": String(describing: speechPermissionState),
            "microphone": String(describing: microphonePermissionState)
        ])
    }

    #if os(iOS)
    private func requestMicrophonePermission() async {
        let current = AVAudioApplication.shared.recordPermission

        switch current {
        case .granted:
            microphonePermissionState = .granted
            return
        case .denied:
            microphonePermissionState = .denied
            return
        case .undetermined:
            break
        @unknown default:
            microphonePermissionState = .denied
            return
        }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        microphonePermissionState = granted ? .granted : .denied
    }
    #endif

    private func updateSpeechPermission(with status: SpeechRecognitionService.AuthorizationStatus) {
        switch status {
        case .authorized:
            speechPermissionState = .granted
        case .denied, .restricted:
            speechPermissionState = .denied
        case .notDetermined:
            speechPermissionState = .unknown
        }
    }

    // MARK: - Recording

    public func startRecording(onTranscript: @escaping (String) -> Void) async {
        guard !isRecording, !isTranscribing else { return }

        // Ensure permissions
        if speechPermissionState != .granted {
            await prefetchPermissions()
        }

        guard speechPermissionState == .granted else {
            setError("Microphone access is required to capture your voice.", autoDismiss: false)
            return
        }

        #if os(iOS)
        guard microphonePermissionState == .granted else {
            setError("Enable microphone access in Settings.", autoDismiss: false)
            return
        }
        #endif

        do {
            try await speechService.start(locale: Locale.current)
            isRecording = true
            recordingStartTime = Date()
            clearError()

            AppLogger.speech().log(event: "voice:recordingStarted", data: [:])
        } catch {
            await handleSpeechError(error)
        }
    }

    public func finishRecording(onTranscript: @escaping (String) -> Void) async {
        guard isRecording else { return }

        isRecording = false
        isTranscribing = true

        do {
            let transcript = try await speechService.stop()
            isTranscribing = false

            // Validate duration
            if let start = recordingStartTime {
                let duration = Date().timeIntervalSince(start)
                if duration < 0.5 {
                    recordingStartTime = nil
                    setError("Hold the microphone a bit longer.")
                    AppLogger.speech().log(event: "voice:recordingTooShort", data: [
                        "durationMs": Int(duration * 1000)
                    ])
                    return
                }
            }

            recordingStartTime = nil

            // Validate transcript
            let cleaned = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleaned.isEmpty else {
                setError("I didn't catch that. Try speaking again.")
                AppLogger.speech().log(event: "voice:transcriptEmpty", data: [:])
                return
            }

            clearError()
            AppLogger.speech().log(event: "voice:transcriptReceived", data: [
                "characters": cleaned.count
            ])

            onTranscript(cleaned)
        } catch {
            isTranscribing = false
            await handleSpeechError(error)
        }
    }

    public func cancelRecording() async {
        recordingStartTime = nil
        await speechService.cancel()
        isRecording = false
        isTranscribing = false
    }

    // MARK: - Error Handling

    public func clearError() {
        errorDismissTask?.cancel()
        errorMessage = nil
    }

    private func setError(_ message: String, autoDismiss: Bool = true) {
        errorDismissTask?.cancel()
        errorMessage = message

        guard autoDismiss else { return }

        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.clearError()
            }
        }
    }

    private func handleSpeechError(_ error: Error) async {
        recordingStartTime = nil

        if let serviceError = error as? SpeechRecognitionService.ServiceError {
            switch serviceError {
            case .authorizationDenied:
                speechPermissionState = .denied
                setError("Microphone access is required to capture your voice.", autoDismiss: false)
            case .onDeviceRecognitionUnsupported:
                setError("On-device speech recognition isn't supported on this device.", autoDismiss: false)
            case .recognizerUnavailable:
                setError("Speech recognizer is currently unavailable.")
            case .audioEngineUnavailable:
                setError("Couldn't access the microphone. Please try again.")
            case .recognitionFailed(let message):
                setError(message)
            case .recognitionAlreadyRunning:
                setError("A recording session is already active.")
            case .noActiveRecognition:
                setError("No recording session to finish.")
            }
            AppLogger.speech().logError(event: "voice:recordingError", error: serviceError)
        } else {
            setError(error.localizedDescription)
            AppLogger.speech().logError(event: "voice:recordingError", error: error)
        }

        await speechService.cancel()
        isRecording = false
        isTranscribing = false
    }
}
