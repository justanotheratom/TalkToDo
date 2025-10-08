import Foundation
import AVFoundation
import AudioToolbox
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
        public let sampleRate: Double
        public let buffers: AsyncStream<PCMBufferPacket>

        public init(id: UUID, sampleRate: Double, buffers: AsyncStream<PCMBufferPacket>) {
            self.id = id
            self.sampleRate = sampleRate
            self.buffers = buffers
        }
    }

    public struct StopResult: Sendable {
        public let audioData: Data
        public let duration: TimeInterval
        public let sampleRate: Double
        public let audioFormat: String

        public init(audioData: Data, duration: TimeInterval, sampleRate: Double, audioFormat: String) {
            self.audioData = audioData
            self.duration = duration
            self.sampleRate = sampleRate
            self.audioFormat = audioFormat
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
                return "Failed to prepare audio encoder for recording."
            case .audioEngineUnavailable:
                return "Audio engine could not be started."
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var recordingStartDate: Date?
    private var buffersContinuation: AsyncStream<PCMBufferPacket>.Continuation?
    private var inputFormat: AVAudioFormat?
    private var sessionConfigured = false
    private var sessionActive = false

    private var extAudioFile: ExtAudioFileRef?
    private var audioFileID: AudioFileID?
    private var memoryFileHandle: Unmanaged<MemoryAudioFile>?
    private var memoryFile: MemoryAudioFile?
    private var targetOutputSampleRate: Double?

    private let targetSampleRate: Double = 12_000
    private let targetChannelCount: AVAudioChannelCount = 1

    private let log = AppLogger.speech()

    public init() {}

    public func startRecording() async throws -> ActiveSession {
        guard audioEngine == nil else { throw CaptureError.alreadyRecording }

        try await configureSessionIfNeeded()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let sourceFormat = inputNode.outputFormat(forBus: 0)
        inputFormat = sourceFormat

        try prepareEncoder(for: sourceFormat)

        let buffers = AsyncStream<PCMBufferPacket> { continuation in
            self.buffersContinuation = continuation
        }

        recordingStartDate = Date()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [weak self] buffer, _ in
            guard let copy = buffer.makeCopy() else { return }
            let packet = PCMBufferPacket(buffer: copy)
            Task { [weak self, packet] in
                await self?.handleIncoming(packet: packet)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            buffersContinuation?.finish()
            buffersContinuation = nil
            cleanupEncoder()
            recordingStartDate = nil
            throw CaptureError.audioEngineUnavailable
        }

        audioEngine = engine
        log.log(event: "audioCapture:started", data: [
            "sourceSampleRate": sourceFormat.sampleRate
        ])

        return ActiveSession(
            id: UUID(),
            sampleRate: sourceFormat.sampleRate,
            buffers: buffers
        )
    }

    public func stopRecording() async throws -> StopResult {
        guard let engine = audioEngine,
              let startDate = recordingStartDate,
              let extAudioFile = extAudioFile,
              let memoryFile = memoryFile,
              let targetSampleRate = targetOutputSampleRate else {
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

        ExtAudioFileDispose(extAudioFile)
        if let audioFileID {
            AudioFileClose(audioFileID)
        }
        memoryFileHandle?.release()

        let outputData = memoryFile.data

        self.extAudioFile = nil
        self.audioFileID = nil
        self.memoryFileHandle = nil
        self.memoryFile = nil
        self.targetOutputSampleRate = nil

        log.log(event: "audioCapture:stopped", data: [
            "durationMs": Int(duration * 1000),
            "encodedBytes": outputData.count
        ])

        guard !outputData.isEmpty else {
            throw CaptureError.unableToCreateFile
        }

        return StopResult(
            audioData: outputData,
            duration: max(duration, 0),
            sampleRate: targetSampleRate,
            audioFormat: "wav"
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

        cleanupEncoder()
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

    private func prepareEncoder(for sourceFormat: AVAudioFormat) throws {
        cleanupEncoder()

        guard let targetFormat = makeTargetFormat() else {
            throw CaptureError.unableToCreateFile
        }

        let memoryStorage = MemoryAudioFile()
        let memoryHandle = Unmanaged.passRetained(memoryStorage)

        var audioFileID: AudioFileID?
        var targetDesc = targetFormat.streamDescription.pointee
        let status = AudioFileInitializeWithCallbacks(
            memoryHandle.toOpaque(),
            MemoryAudioFile.readProc,
            MemoryAudioFile.writeProc,
            MemoryAudioFile.getSizeProc,
            MemoryAudioFile.setSizeProc,
            kAudioFileWAVEType,
            &targetDesc,
            AudioFileFlags(rawValue: 0),
            &audioFileID
        )

        guard status == noErr, let audioFileID else {
            memoryHandle.release()
            throw CaptureError.unableToCreateFile
        }

        var extFile: ExtAudioFileRef?
        let wrapStatus = ExtAudioFileWrapAudioFileID(audioFileID, true, &extFile)
        guard wrapStatus == noErr, let extFile else {
            AudioFileClose(audioFileID)
            memoryHandle.release()
            throw CaptureError.unableToCreateFile
        }

        var clientDesc = sourceFormat.streamDescription.pointee
        let clientStatus = ExtAudioFileSetProperty(
            extFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientDesc
        )

        guard clientStatus == noErr else {
            ExtAudioFileDispose(extFile)
            AudioFileClose(audioFileID)
            memoryHandle.release()
            throw CaptureError.unableToCreateFile
        }

        self.extAudioFile = extFile
        self.audioFileID = audioFileID
        self.memoryFile = memoryStorage
        self.memoryFileHandle = memoryHandle
        self.targetOutputSampleRate = targetFormat.sampleRate

        log.log(event: "audioCapture:encoderPrepared", data: [
            "formatID": formatName(for: targetDesc.mFormatID),
            "sampleRate": targetFormat.sampleRate,
            "channels": targetFormat.channelCount
        ])
    }

    private func cleanupEncoder() {
        if let extAudioFile {
            ExtAudioFileDispose(extAudioFile)
        }
        extAudioFile = nil
        if let audioFileID {
            AudioFileClose(audioFileID)
        }
        audioFileID = nil
        memoryFileHandle?.release()
        memoryFileHandle = nil
        memoryFile = nil
        targetOutputSampleRate = nil
    }

    private func makeTargetFormat() -> AVAudioFormat? {
        if let ulaw = AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatULaw,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannelCount)
        ]) {
            return ulaw
        }

        return AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
    }

    private func formatName(for formatID: AudioFormatID) -> String {
        switch formatID {
        case kAudioFormatLinearPCM:
            return "linearPCM"
        case kAudioFormatULaw:
            return "ulaw"
        case kAudioFormatALaw:
            return "alaw"
        case kAudioFormatMPEG4AAC:
            return "aac"
        default:
            return String(format: "0x%08x", formatID)
        }
    }

    private func handleIncoming(packet: PCMBufferPacket) {
        buffersContinuation?.yield(packet)

        guard let extAudioFile else { return }
        let frameCount = UInt32(packet.buffer.frameLength)
        guard frameCount > 0 else { return }

        let status = ExtAudioFileWrite(extAudioFile, frameCount, packet.buffer.audioBufferList)

        if status != noErr {
            log.log(event: "audioCapture:writeError", data: [
                "status": status
            ])
        }
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

private final class MemoryAudioFile {
    fileprivate var data = Data()

    static let readProc: AudioFile_ReadProc = { inClientData, inPosition, requestCount, buffer, actualCount in
        let storage = Unmanaged<MemoryAudioFile>.fromOpaque(inClientData).takeUnretainedValue()
        let available = max(0, storage.data.count - Int(inPosition))
        let copyCount = min(Int(requestCount), available)

        if copyCount > 0 {
            storage.data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else {
                    actualCount.pointee = 0
                    return
                }
                memcpy(buffer, base.advanced(by: Int(inPosition)), copyCount)
            }
        }

        actualCount.pointee = UInt32(copyCount)
        return noErr
    }

    static let writeProc: AudioFile_WriteProc = { inClientData, inPosition, requestCount, buffer, actualCount in
        let storage = Unmanaged<MemoryAudioFile>.fromOpaque(inClientData).takeUnretainedValue()
        let requiredSize = Int(inPosition) + Int(requestCount)
        if storage.data.count < requiredSize {
            storage.data.append(Data(count: requiredSize - storage.data.count))
        }

        storage.data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            memcpy(base.advanced(by: Int(inPosition)), buffer, Int(requestCount))
        }

        actualCount.pointee = requestCount
        return noErr
    }

    static let getSizeProc: AudioFile_GetSizeProc = { inClientData in
        let storage = Unmanaged<MemoryAudioFile>.fromOpaque(inClientData).takeUnretainedValue()
        return Int64(storage.data.count)
    }

    static let setSizeProc: AudioFile_SetSizeProc = { inClientData, inSize in
        let storage = Unmanaged<MemoryAudioFile>.fromOpaque(inClientData).takeUnretainedValue()
        let newSize = Int(inSize)
        if storage.data.count < newSize {
            storage.data.append(Data(count: newSize - storage.data.count))
        } else if storage.data.count > newSize {
            storage.data.removeSubrange(newSize..<storage.data.count)
        }
        return noErr
    }
}
