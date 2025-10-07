import XCTest
@testable import TalkToDoFeature
@testable import TalkToDoShared

final class TalkToDoFeatureTests: XCTestCase {
    @MainActor
    func testSettingsStorePersistsMode() {
        let suiteName = "com.talktodo.tests.settings"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = VoiceProcessingSettingsStore(defaults: defaults)
        XCTAssertEqual(store.mode, .onDevice)

        store.update(mode: .remoteGemini)

        let reloaded = VoiceProcessingSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.mode, .remoteGemini)
    }

    func testGeminiClientThrowsWhenKeyMissing() async {
        let baseURL = URL(string: "https://example.com")!
        let configuration = GeminiAPIClient.Configuration(baseURL: baseURL, apiKey: "")
        let client = GeminiAPIClient(configuration: configuration)

        do {
            _ = try await client.submitTask(audioURL: nil, transcript: "hello", localeIdentifier: nil)
            XCTFail("Expected missing API key error")
        } catch let error as GeminiAPIClient.ClientError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiClientThrowsWhenAudioMissing() async {
        let baseURL = URL(string: "https://example.com")!
        let configuration = GeminiAPIClient.Configuration(baseURL: baseURL, apiKey: "abc123")
        let client = GeminiAPIClient(configuration: configuration)

        do {
            _ = try await client.submitTask(audioURL: URL(fileURLWithPath: "/tmp/does-not-exist.caf"), transcript: "hi", localeIdentifier: nil)
            XCTFail("Expected missing audio error")
        } catch let error as GeminiAPIClient.ClientError {
            XCTAssertEqual(error, .missingAudioFile)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiPipelineUsesRemoteForTextOnly() async throws {
        let response = GeminiStructuredResponse(transcript: "remote", operations: [])
        let client = StubGeminiClient(result: .success(response))
        let fallbackResult = OperationGenerationResult(transcript: "fallback", operations: [])
        let fallbackPipeline = StubTextPipeline(result: fallbackResult)
        let pipeline = GeminiTextPipeline(
            client: client,
            fallback: AnyTextProcessingPipeline(fallbackPipeline)
        )

        let result = try await pipeline.process(text: "type text", nodeContext: nil)
        XCTAssertEqual(result.transcript, "remote")
        XCTAssertFalse(fallbackPipeline.didProcess)
        XCTAssertNil(client.capturedAudioURL)
        XCTAssertEqual(client.capturedTranscript, "type text")
    }

    func testGeminiPipelineFallsBackOnClientError() async throws {
        let client = StubGeminiClient(result: .failure(GeminiAPIClient.ClientError.invalidResponse))
        let fallbackResult = OperationGenerationResult(transcript: "fallback", operations: [])
        let fallbackPipeline = StubTextPipeline(result: fallbackResult)
        let pipeline = GeminiTextPipeline(
            client: client,
            fallback: AnyTextProcessingPipeline(fallbackPipeline)
        )

        let result = try await pipeline.process(text: "hi", nodeContext: nil)
        XCTAssertEqual(result.transcript, fallbackResult.transcript)
        XCTAssertTrue(fallbackPipeline.didProcess)
    }
}

private final class StubGeminiClient: @unchecked Sendable, GeminiClientProtocol {
    let result: Result<GeminiStructuredResponse, Error>
    private(set) var capturedAudioURL: URL?
    private(set) var capturedTranscript: String?

    init(result: Result<GeminiStructuredResponse, Error>) {
        self.result = result
    }

    func submitTask(
        audioURL: URL?,
        transcript: String?,
        localeIdentifier: String?
    ) async throws -> GeminiStructuredResponse {
        capturedAudioURL = audioURL
        capturedTranscript = transcript
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private final class StubVoicePipeline: @unchecked Sendable, VoiceProcessingPipeline {
    let result: OperationGenerationResult
    private(set) var invocationCount = 0

    init(result: OperationGenerationResult) {
        self.result = result
    }

    var didProcess: Bool { invocationCount > 0 }

    func process(
        metadata: RecordingMetadata,
        nodeContext: NodeContext?
    ) async throws -> OperationGenerationResult {
        invocationCount += 1
        return result
    }
}

private final class StubTextPipeline: @unchecked Sendable, TextProcessingPipeline {
    let result: OperationGenerationResult
    private(set) var invocationCount = 0

    init(result: OperationGenerationResult) {
        self.result = result
    }

    var didProcess: Bool { invocationCount > 0 }

    func process(text: String, nodeContext: NodeContext?) async throws -> OperationGenerationResult {
        invocationCount += 1
        return result
    }
}
