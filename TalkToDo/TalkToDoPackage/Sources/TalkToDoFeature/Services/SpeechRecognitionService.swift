import Foundation
import AVFoundation
@preconcurrency import Speech
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct SpeechRecognitionResult: Sendable {
    public let transcript: String?
    public let duration: TimeInterval
    public let sampleRate: Double?

    public init(transcript: String?, duration: TimeInterval, sampleRate: Double?) {
        self.transcript = transcript
        self.duration = duration
        self.sampleRate = sampleRate
    }
}

@available(iOS 18.0, macOS 15.0, *)
public actor SpeechRecognitionService {
    enum AuthorizationStatus: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted

        init(_ status: SFSpeechRecognizerAuthorizationStatus) {
            switch status {
            case .authorized:
                self = .authorized
            case .denied:
                self = .denied
            case .restricted:
                self = .restricted
            case .notDetermined:
                fallthrough
            @unknown default:
                self = .notDetermined
            }
        }
    }

    enum ServiceError: Error, LocalizedError, Equatable {
        case recognizerUnavailable
        case onDeviceRecognitionUnsupported
        case authorizationDenied
        case audioEngineUnavailable
        case recognitionAlreadyRunning
        case noActiveRecognition
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition is not available for the selected locale."
            case .onDeviceRecognitionUnsupported:
                return "On-device speech recognition is unavailable on this device."
            case .authorizationDenied:
                return "Speech recognition permission was denied."
            case .audioEngineUnavailable:
                return "Could not start audio capture."
            case .recognitionAlreadyRunning:
                return "Speech recognition session is already active."
            case .noActiveRecognition:
                return "There is no active speech session to stop."
            case .recognitionFailed(let message):
                return message
            }
        }
    }

    private enum State: Equatable { case idle, recording }

    private var state: State = .idle
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String?, Error>?
    private var latestTranscription: String?
    private var localeProvider: () -> Locale
    private var sessionConfigured = false
    private var sessionActive = false

    public init(localeProvider: @escaping () -> Locale = { Locale.current }) {
        self.localeProvider = localeProvider
    }

    func authorizationStatus() -> AuthorizationStatus {
        AuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
    }

    func requestAuthorization() async -> AuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: AuthorizationStatus(status))
            }
        }
    }

    func start(locale overrideLocale: Locale? = nil) async throws {
        let logger = AppLogger.speech()
        let startTime = Date()
        logger.log(event: "speech:startRequested", data: [
            "state": String(describing: state),
            "overrideLocale": overrideLocale?.identifier ?? "nil"
        ])
        guard state == .idle else { throw ServiceError.recognitionAlreadyRunning }

        let locale = overrideLocale ?? localeProvider()
        let recognizer: SFSpeechRecognizer
        if let existing = speechRecognizer, existing.locale == locale {
            recognizer = existing
        } else if let existing = speechRecognizer, overrideLocale == nil {
            recognizer = existing
        } else {
            guard let created = SFSpeechRecognizer(locale: locale) else {
                throw ServiceError.recognizerUnavailable
            }
            speechRecognizer = created
            recognizer = created
        }
        logger.log(event: "speech:recognizerInitialized", data: [
            "locale": locale.identifier,
            "onDevice": recognizer.supportsOnDeviceRecognition,
            "available": recognizer.isAvailable
        ])

        guard recognizer.supportsOnDeviceRecognition else {
            throw ServiceError.onDeviceRecognitionUnsupported
        }

        guard recognizer.isAvailable else {
            throw ServiceError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        #if os(iOS)
        logger.log(event: "speech:audioSessionConfigStart", data: [
            "configured": sessionConfigured,
            "active": sessionActive
        ])

        if !sessionConfigured {
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.duckOthers]
                )
            }
            sessionConfigured = true
        }

        if !sessionActive {
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            }
            sessionActive = true
        }

        logger.log(event: "speech:audioSessionConfigEnd", data: [
            "elapsedMs": Int(Date().timeIntervalSince(startTime) * 1000),
            "active": sessionActive
        ])
        #endif

        recognitionRequest = request
        speechRecognizer = recognizer
        latestTranscription = nil

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorInfo = (error as NSError?)
            Task { await self.processRecognitionUpdate(transcript: transcript, isFinal: isFinal, error: errorInfo) }
        }
        logger.log(event: "speech:recognitionTaskCreated", data: [:])

        state = .recording
        logger.log(event: "speech:startCompleted", data: [
            "totalMs": Int(Date().timeIntervalSince(startTime) * 1000)
        ])
    }

    func append(buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stop(duration: TimeInterval, sampleRate: Double?) async throws -> SpeechRecognitionResult {
        let logger = AppLogger.speech()
        logger.log(event: "speech:stopRequested", data: [
            "state": String(describing: state)
        ])
        guard state == .recording else { throw ServiceError.noActiveRecognition }

        // Stop audio input
        recognitionRequest?.endAudio()

        // Wait for final result with timeout, fallback to latest partial result
        let result: String? = try await withThrowingTaskGroup(of: String?.self) { [weak self] group in
            guard let self else { throw ServiceError.noActiveRecognition }

            // Task 1: Wait for final recognition result
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { continuation in
                    guard let self else {
                        continuation.resume(throwing: ServiceError.noActiveRecognition)
                        return
                    }
                    Task {
                        await self.setFinishContinuation(continuation)
                    }
                }
            }

            // Task 2: Timeout fallback - return partial transcript if available
            group.addTask { [weak self] in
                try await Task.sleep(for: .seconds(1.5))
                return await self?.latestTranscription
            }

            // Return first result (either final or timeout fallback)
            guard let result = try await group.next() else {
                throw ServiceError.recognitionFailed("No result received")
            }

            group.cancelAll()
            return result
        }

        let sanitizedDuration = duration > 0 ? duration : 0

        await cleanup()
        logger.log(event: "speech:stopCompleted", data: [
            "durationMs": Int(sanitizedDuration * 1000),
            "hasTranscript": result != nil
        ])
        return SpeechRecognitionResult(
            transcript: result,
            duration: sanitizedDuration,
            sampleRate: sampleRate
        )
    }

    private func setFinishContinuation(_ continuation: CheckedContinuation<String?, Error>) {
        finishContinuation = continuation
    }

    func cancel() async {
        let logger = AppLogger.speech()
        logger.log(event: "speech:cancelRequested", data: [
            "state": String(describing: state)
        ])
        if let continuation = finishContinuation {
            continuation.resume(throwing: ServiceError.recognitionFailed("Cancelled"))
            finishContinuation = nil
        }
        await cleanup()
        logger.log(event: "speech:cancelCompleted", data: [:])
    }

    func getCurrentTranscript() -> String? {
        latestTranscription
    }

    private func processRecognitionUpdate(transcript: String?, isFinal: Bool, error: NSError?) async {
        let logger = AppLogger.speech()
        logger.log(event: "speech:recognitionUpdate", data: [
            "isFinal": isFinal,
            "hasTranscript": transcript != nil,
            "transcriptLength": transcript?.count ?? 0
        ])
        if let error {
            if let continuation = finishContinuation {
                continuation.resume(throwing: ServiceError.recognitionFailed(error.localizedDescription))
                finishContinuation = nil
            }
            return
        }

        if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latestTranscription = transcript
        }

        if isFinal {
            if let continuation = finishContinuation {
                let finalTranscript: String?
                if let latestTranscription {
                    finalTranscript = latestTranscription
                } else if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalTranscript = transcript
                } else {
                    finalTranscript = nil
                }
                continuation.resume(returning: finalTranscript)
                finishContinuation = nil
            }
        }
    }

    private func cleanup() async {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        latestTranscription = nil
        state = .idle
    }

    func prewarmRecognizer() async {
        if speechRecognizer != nil { return }
        let locale = localeProvider()
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return }
        speechRecognizer = recognizer
        _ = recognizer.isAvailable
        if recognizer.supportsOnDeviceRecognition {
            AppLogger.speech().log(event: "speech:recognizerPrewarmed", data: [
                "locale": locale.identifier
            ])
        } else {
            AppLogger.speech().log(event: "speech:recognizerPrewarmFallback", data: [
                "locale": locale.identifier
            ])
        }
    }

    func prepareSession() async {
        #if os(iOS)
        let needsCategory = !sessionConfigured
        let needsActivation = !sessionActive
        guard needsCategory || needsActivation else { return }
        do {
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                if needsCategory {
                    try audioSession.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.duckOthers]
                    )
                }
                if needsActivation {
                    try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
                }
            }
            if needsCategory { sessionConfigured = true }
            if needsActivation { sessionActive = true }
            AppLogger.speech().log(event: "speech:sessionPrepared", data: [
                "configured": sessionConfigured,
                "active": sessionActive
            ])
        } catch {
            AppLogger.speech().logError(event: "speech:sessionPrepareFailed", error: error)
        }
        #else
        sessionConfigured = true
        sessionActive = true
        #endif
    }
}
