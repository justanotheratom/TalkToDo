import Foundation

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
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult
}

public protocol TextProcessingPipeline: Sendable {
    func process(
        text: String,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult
}
