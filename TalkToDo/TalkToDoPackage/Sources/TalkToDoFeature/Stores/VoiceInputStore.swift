import Foundation
import Observation
import TalkToDoShared

#if os(iOS)
import AVFoundation
#endif
@preconcurrency import Speech

// MARK: - Timeout Helper

/// Executes an async operation with a timeout
private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Operation timed out"
    }
}

/// Store managing voice input UI state
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class VoiceInputStore {
    public enum Status: Equatable {
        case idle
        case requestingPermission
        case recording
        case transcribing
        case disabled(message: String)
        case error(message: String)

        public var allowsInteraction: Bool {
            switch self {
            case .idle, .error:
                return true
            case .requestingPermission, .recording, .transcribing, .disabled:
                return false
            }
        }
    }

    public enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    // MARK: - Published State

    public var isRecording = false
    public var isTranscribing = false
    public var isRequestingPermission = false
    public var speechPermissionState: PermissionState = .unknown
    public var microphonePermissionState: PermissionState = .unknown
    public var errorMessage: String?
    public var liveTranscript: String?

    // MARK: - Dependencies

    @ObservationIgnored private let speechService: SpeechRecognitionService
    @ObservationIgnored private var recordingStartTime: Date?
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?
    @ObservationIgnored private var completionHandler: ((RecordingMetadata) -> Void)?
    @ObservationIgnored private var transcriptPollingTask: Task<Void, Never>?
    @ObservationIgnored private var recordingLocaleIdentifier: String?

    // MARK: - Initialization

    public init(speechService: SpeechRecognitionService = SpeechRecognitionService()) {
        self.speechService = speechService

        // Seed permission state from system so first recording doesn't block on refresh
        let speechStatus = SpeechRecognitionService.AuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        updateSpeechPermission(with: speechStatus)

        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphonePermissionState = .granted
        case .denied:
            microphonePermissionState = .denied
        case .undetermined:
            microphonePermissionState = .unknown
        @unknown default:
            microphonePermissionState = .unknown
        }
        #else
        microphonePermissionState = .granted
        #endif
    }

    deinit {
        errorDismissTask?.cancel()
        transcriptPollingTask?.cancel()
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
        if isRequestingPermission {
            return .requestingPermission
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
            isRequestingPermission = true
            let requested = await speechService.requestAuthorization()
            isRequestingPermission = false
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

        isRequestingPermission = true
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        isRequestingPermission = false

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

    public func startRecording(onComplete: @escaping (RecordingMetadata) -> Void) async {
        guard !isRecording, !isTranscribing else { return }

        let logger = AppLogger.speech()
        let startTimestamp = Date()
        let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        let timestamp = isoFormatter.string(from: startTimestamp)
        logger.log(event: "voice:startRecordingInvoked", data: [
            "speechPermission": String(describing: speechPermissionState),
            "microphonePermission": String(describing: microphonePermissionState),
            "isRequesting": isRequestingPermission,
            "timestamp": timestamp
        ])

        // Ensure permissions
        if speechPermissionState != .granted {
            logger.log(event: "voice:startRecordingPrefetchingPermissions", data: [:])
            await prefetchPermissions()
            logger.log(event: "voice:startRecordingPrefetchCompleted", data: [
                "speechPermission": String(describing: speechPermissionState),
                "microphonePermission": String(describing: microphonePermissionState),
                "elapsedMs": Int(Date().timeIntervalSince(startTimestamp) * 1000)
            ])
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
            logger.log(event: "voice:startRecordingStartingSpeech", data: [:])
            let locale = Locale.current
            try await speechService.start(locale: locale)
            let elapsedMs = Int(Date().timeIntervalSince(startTimestamp) * 1000)
            logger.log(event: "voice:startRecordingSpeechStarted", data: [
                "elapsedMs": elapsedMs,
                "locale": locale.identifier,
                "timestamp": isoFormatter.string(from: Date())
            ])
            completionHandler = onComplete
            recordingLocaleIdentifier = locale.identifier
            isRecording = true
            recordingStartTime = Date()
            clearError()
            startTranscriptPolling()

            AppLogger.speech().log(event: "voice:recordingStarted", data: [:])
        } catch {
            completionHandler = nil
            recordingLocaleIdentifier = nil
            logger.log(event: "voice:startRecordingFailed", data: [
                "elapsedMs": Int(Date().timeIntervalSince(startTimestamp) * 1000),
                "timestamp": isoFormatter.string(from: Date())
            ])
            await handleSpeechError(error)
        }
    }

    public func finishRecording() async {
        guard isRecording else {
            AppLogger.speech().log(event: "voice:finishRecordingSkipped", data: ["reason": "notRecording"])
            return
        }

        let finalHandler = completionHandler
        completionHandler = nil

        AppLogger.speech().log(event: "voice:finishRecordingStarted", data: [:])
        isRecording = false
        isTranscribing = true
        stopTranscriptPolling()

        do {
            AppLogger.speech().log(event: "voice:stoppingRecognition", data: [:])

            // Add timeout to prevent infinite hang
            let recognitionResult = try await withTimeout(seconds: 10) { [speechService] in
                try await speechService.stop()
            }

            AppLogger.speech().log(event: "voice:recognitionStopped", data: [
                "hasTranscript": recognitionResult.transcript != nil
            ])
            isTranscribing = false

            // Validate duration
            if let start = recordingStartTime {
                let duration = Date().timeIntervalSince(start)
                AppLogger.speech().log(event: "voice:validateDuration", data: [
                    "durationMs": Int(duration * 1000)
                ])
                if duration < 0.5 {
                    recordingStartTime = nil
                    setError("Hold the microphone a bit longer.")
                    AppLogger.speech().log(event: "voice:recordingTooShort", data: [
                        "durationMs": Int(duration * 1000)
                    ])
                    recordingLocaleIdentifier = nil
                    return
                }
            }

            recordingStartTime = nil

            // Validate transcript
            let cleaned = recognitionResult.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            AppLogger.speech().log(event: "voice:validateTranscript", data: [
                "length": cleaned.count,
                "isEmpty": cleaned.isEmpty
            ])
            guard !cleaned.isEmpty else {
                setError("I didn't catch that. Try speaking again.")
                AppLogger.speech().log(event: "voice:transcriptEmpty", data: [:])
                recordingLocaleIdentifier = nil
                return
            }

            clearError()
            AppLogger.speech().log(event: "voice:transcriptReceived", data: [
                "characters": cleaned.count
            ])
            liveTranscript = nil

            if let finalHandler {
                let localeId = recordingLocaleIdentifier ?? Locale.current.identifier
                let metadata = RecordingMetadata(
                    transcript: cleaned,
                    audioURL: recognitionResult.audioURL,
                    duration: recognitionResult.duration,
                    sampleRate: recognitionResult.sampleRate,
                    localeIdentifier: localeId
                )

                AppLogger.speech().log(event: "voice:callingCompletion", data: [
                    "hasAudio": metadata.audioURL != nil
                ])
                finalHandler(metadata)
                AppLogger.speech().log(event: "voice:completionInvoked", data: [:])
            }

            recordingLocaleIdentifier = nil
        } catch {
            AppLogger.speech().log(event: "voice:finishRecordingError", data: [
                "error": error.localizedDescription
            ])
            isTranscribing = false
            recordingLocaleIdentifier = nil
            await handleSpeechError(error)
        }
    }

    public func cancelRecording() async {
        recordingStartTime = nil
        stopTranscriptPolling()
        completionHandler = nil
        liveTranscript = nil
        await speechService.cancel()
        isRecording = false
        isTranscribing = false
        recordingLocaleIdentifier = nil
    }

    private func startTranscriptPolling() {
        transcriptPollingTask?.cancel()
        transcriptPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.pollTranscriptLoop()
        }
    }

    @MainActor
    private func pollTranscriptLoop() async {
        while !Task.isCancelled {
            let transcript = await speechService.getCurrentTranscript()
            if let transcript, !transcript.isEmpty {
                if liveTranscript != transcript {
                    liveTranscript = transcript
                }
            } else if liveTranscript != nil {
                liveTranscript = nil
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func stopTranscriptPolling() {
        transcriptPollingTask?.cancel()
        transcriptPollingTask = nil
        liveTranscript = nil
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
        stopTranscriptPolling()
        completionHandler = nil
        liveTranscript = nil
        recordingLocaleIdentifier = nil

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
