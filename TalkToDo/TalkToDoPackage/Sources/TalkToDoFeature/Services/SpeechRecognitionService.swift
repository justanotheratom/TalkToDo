import Foundation
import AVFoundation
@preconcurrency import Speech
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct SpeechRecognitionResult: Sendable {
    public let transcript: String?
    public let audioURL: URL?
    public let duration: TimeInterval
    public let sampleRate: Double?

    public init(transcript: String?, audioURL: URL?, duration: TimeInterval, sampleRate: Double?) {
        self.transcript = transcript
        self.audioURL = audioURL
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
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String?, Error>?
    private var latestTranscription: String?
    private var localeProvider: () -> Locale
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartDate: Date?
    private var recordingSampleRate: Double?

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
        logger.log(event: "speech:startRequested", data: [
            "state": String(describing: state),
            "overrideLocale": overrideLocale?.identifier ?? "nil"
        ])
        guard state == .idle else { throw ServiceError.recognitionAlreadyRunning }

        let locale = overrideLocale ?? localeProvider()
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ServiceError.recognizerUnavailable
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

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        #if os(iOS)
        try await MainActor.run {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        #endif

        recognitionRequest = request
        self.audioEngine = audioEngine
        speechRecognizer = recognizer
        latestTranscription = nil

        let inputNode = audioEngine.inputNode

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        recordingSampleRate = recordingFormat.sampleRate
        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("talktodo-recording-\(UUID().uuidString).wav")
            recordingFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
            recordingURL = fileURL
        } catch {
            recordingFile = nil
            recordingURL = nil
        }
        inputNode.removeTap(onBus: 0)
        let recordingFileReference = recordingFile
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
            if let file = recordingFileReference {
                try? file.write(from: buffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            logger.log(event: "speech:audioEngineStarted", data: [
                "sampleRate": recordingFormat.sampleRate
            ])
        } catch {
            inputNode.removeTap(onBus: 0)
            throw ServiceError.audioEngineUnavailable
        }

        recordingStartDate = Date()
        state = .recording

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorInfo = (error as NSError?)
            Task { await self.processRecognitionUpdate(transcript: transcript, isFinal: isFinal, error: errorInfo) }
        }
        logger.log(event: "speech:recognitionTaskCreated", data: [
            "hasRecordingFile": recordingFile != nil
        ])
    }

    func stop() async throws -> SpeechRecognitionResult {
        let logger = AppLogger.speech()
        logger.log(event: "speech:stopRequested", data: [
            "state": String(describing: state)
        ])
        guard state == .recording else { throw ServiceError.noActiveRecognition }

        // Stop audio input
        recognitionRequest?.endAudio()
        audioEngine?.stop()

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

        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let sanitizedDuration = duration > 0 ? duration : 0
        let audioURL = recordingURL
        let sampleRate = recordingSampleRate

        await cleanup()
        logger.log(event: "speech:stopCompleted", data: [
            "durationMs": Int(sanitizedDuration * 1000),
            "hasTranscript": result != nil,
            "hasAudio": audioURL != nil
        ])
        return SpeechRecognitionResult(
            transcript: result,
            audioURL: audioURL,
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
        discardRecordedAudio()
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

        if let transcript {
            latestTranscription = transcript
        }

        if isFinal {
            if let continuation = finishContinuation {
                continuation.resume(returning: latestTranscription)
                finishContinuation = nil
            }
        }
    }

    private func cleanup() async {
        let logger = AppLogger.speech()
        logger.log(event: "speech:cleanup", data: [
            "hadRecording": recordingURL != nil
        ])
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        latestTranscription = nil
        recordingFile = nil
        recordingURL = nil
        recordingStartDate = nil
        recordingSampleRate = nil
        state = .idle

        #if os(iOS)
        await MainActor.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    private func discardRecordedAudio() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
