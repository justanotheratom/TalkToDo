import Foundation
import TalkToDoShared

public struct RecordingMetadata: Sendable {
    public let transcript: String?
    public let audioURL: URL?
    public let duration: TimeInterval
    public let sampleRate: Double?
    public let localeIdentifier: String?

    public init(
        transcript: String?,
        audioURL: URL?,
        duration: TimeInterval,
        sampleRate: Double?,
        localeIdentifier: String?
    ) {
        self.transcript = transcript
        self.audioURL = audioURL
        self.duration = duration
        self.sampleRate = sampleRate
        self.localeIdentifier = localeIdentifier
    }

    public static func empty() -> RecordingMetadata {
        RecordingMetadata(
            transcript: nil,
            audioURL: nil,
            duration: 0,
            sampleRate: nil,
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
