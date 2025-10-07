import Foundation
import AVFoundation
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public actor AudioCaptureService {
    public struct PCMBufferPacket: @unchecked Sendable {
        public let buffer: AVAudioPCMBuffer
        public init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }
    }

    public struct ActiveSession: Sendable {
        public let id: UUID
        public let audioURL: URL
        public let sampleRate: Double
        public let buffers: AsyncStream<PCMBufferPacket>

        public init(id: UUID, audioURL: URL, sampleRate: Double, buffers: AsyncStream<PCMBufferPacket>) {
            self.id = id
            self.audioURL = audioURL
            self.sampleRate = sampleRate
            self.buffers = buffers
        }
    }

    public struct StopResult: Sendable {
        public let audioURL: URL
        public let duration: TimeInterval
        public let sampleRate: Double

        public init(audioURL: URL, duration: TimeInterval, sampleRate: Double) {
            self.audioURL = audioURL
            self.duration = duration
            self.sampleRate = sampleRate
        }
    }

    public enum CaptureError: Error, LocalizedError {
        case alreadyRecording
        case noActiveRecording
        case unableToCreateFile
        case audioEngineUnavailable

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "Audio capture is already running."
            case .noActiveRecording:
                return "No active audio capture session."
            case .unableToCreateFile:
                return "Failed to prepare audio file for recording."
            case .audioEngineUnavailable:
                return "Audio engine could not be started."
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var recordingFile: AVAudioFile?
    private var recordingStartDate: Date?
    private var buffersContinuation: AsyncStream<PCMBufferPacket>.Continuation?
    private var inputFormat: AVAudioFormat?
    private var sessionConfigured = false
    private var sessionActive = false
    private let log = AppLogger.speech()

    public init() {}

    public func startRecording() async throws -> ActiveSession {
        guard audioEngine == nil else { throw CaptureError.alreadyRecording }

        try await configureSessionIfNeeded()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputFormat = format

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talktodo-capture-\(UUID().uuidString).wav")
        guard let file = try? AVAudioFile(forWriting: fileURL, settings: format.settings) else {
            throw CaptureError.unableToCreateFile
        }

        let buffers = AsyncStream<PCMBufferPacket> { continuation in
            self.buffersContinuation = continuation
        }

        recordingFile = file
        recordingStartDate = Date()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let packet = buffer.makeCopy().map(PCMBufferPacket.init) else { return }
            Task { await self.handleIncoming(packet: packet) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            buffersContinuation?.finish()
            buffersContinuation = nil
            recordingFile = nil
            recordingStartDate = nil
            throw CaptureError.audioEngineUnavailable
        }

        audioEngine = engine
        log.log(event: "audioCapture:started", data: [
            "sampleRate": format.sampleRate
        ])

        return ActiveSession(
            id: UUID(),
            audioURL: fileURL,
            sampleRate: format.sampleRate,
            buffers: buffers
        )
    }

    public func stopRecording() async throws -> StopResult {
        guard let engine = audioEngine,
              let startDate = recordingStartDate,
              let file = recordingFile,
              let format = inputFormat else {
            throw CaptureError.noActiveRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        buffersContinuation?.finish()
        buffersContinuation = nil

        let duration = Date().timeIntervalSince(startDate)
        recordingStartDate = nil
        inputFormat = nil
        recordingFile = nil

        log.log(event: "audioCapture:stopped", data: [
            "durationMs": Int(duration * 1000)
        ])

        return StopResult(
            audioURL: file.url,
            duration: max(duration, 0),
            sampleRate: format.sampleRate
        )
    }

    public func cancelRecording() async {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        buffersContinuation?.finish()
        buffersContinuation = nil
        recordingStartDate = nil
        inputFormat = nil
        if let url = recordingFile?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFile = nil
    }

    private func configureSessionIfNeeded() async throws {
        #if os(iOS)
        let needsCategory = !sessionConfigured
        let needsActivation = !sessionActive
        guard needsCategory || needsActivation else { return }
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
        #endif
    }

    private func handleIncoming(packet: PCMBufferPacket) {
        buffersContinuation?.yield(packet)
        try? recordingFile?.write(from: packet.buffer)
    }
}

private extension AVAudioPCMBuffer {
    func makeCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        let channelCount = Int(format.channelCount)
        if let src = floatChannelData, let dst = copy.floatChannelData {
            let bytes = Int(frameLength) * MemoryLayout<Float>.size
            for channel in 0..<channelCount {
                memcpy(dst[channel], src[channel], bytes)
            }
            return copy
        }

        if let src = int16ChannelData, let dst = copy.int16ChannelData {
            let bytes = Int(frameLength) * MemoryLayout<Int16>.size
            for channel in 0..<channelCount {
                memcpy(dst[channel], src[channel], bytes)
            }
            return copy
        }

        if let src = int32ChannelData, let dst = copy.int32ChannelData {
            let bytes = Int(frameLength) * MemoryLayout<Int32>.size
            for channel in 0..<channelCount {
                memcpy(dst[channel], src[channel], bytes)
            }
            return copy
        }

        return nil
    }
}
