import Foundation
import TalkToDoShared

public struct RecordingMetadata: Sendable {
    public let transcript: String?
    public let audioURL: URL?
    public let audioData: Data?
    public let duration: TimeInterval
    public let sampleRate: Double?
    public let audioFormat: String?
    public let localeIdentifier: String?

    public init(
        transcript: String?,
        audioURL: URL?,
        audioData: Data? = nil,
        duration: TimeInterval,
        sampleRate: Double?,
        audioFormat: String? = nil,
        localeIdentifier: String?
    ) {
        self.transcript = transcript
        self.audioURL = audioURL
        self.audioData = audioData
        self.duration = duration
        self.sampleRate = sampleRate
        self.audioFormat = audioFormat
        self.localeIdentifier = localeIdentifier
    }

    public static func empty() -> RecordingMetadata {
        RecordingMetadata(
            transcript: nil,
            audioURL: nil,
            audioData: nil,
            duration: 0,
            sampleRate: nil,
            audioFormat: nil,
            localeIdentifier: nil
        )
    }
}

public struct ProcessingContext: Sendable {
    public let nodeContext: NodeContext?
    public let eventLog: [EventLogEntry]
    public let nodeSnapshot: [SnapshotNode]

    public init(nodeContext: NodeContext?, eventLog: [EventLogEntry], nodeSnapshot: [SnapshotNode]) {
        self.nodeContext = nodeContext
        self.eventLog = eventLog
        self.nodeSnapshot = nodeSnapshot
    }

    public static func empty() -> ProcessingContext {
        ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
    }
}

public struct OperationGenerationResult: Sendable {
    public let transcript: String
    public let operations: [Operation]

    public init(transcript: String, operations: [Operation]) {
        self.transcript = transcript
        self.operations = operations
    }
}

public protocol VoiceProcessingPipeline: Sendable {
    func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult
}

public protocol TextProcessingPipeline: Sendable {
    func process(
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult
}
