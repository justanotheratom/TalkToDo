import SwiftData
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
        let pipeline = GeminiTextPipeline(client: client)

        let result = try await pipeline.process(text: "type text", nodeContext: nil)
        XCTAssertEqual(result.transcript, "remote")
        XCTAssertNil(client.capturedAudioURL)
        XCTAssertEqual(client.capturedTranscript, "type text")
    }

    func testGeminiPipelinePropagatesClientError() async {
        let client = StubGeminiClient(result: .failure(GeminiAPIClient.ClientError.invalidResponse))
        let pipeline = GeminiTextPipeline(client: client)

        do {
            _ = try await pipeline.process(text: "hi", nodeContext: nil)
            XCTFail("Expected invalid response error")
        } catch let error as GeminiAPIClient.ClientError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testOperationExecutorResolvesParentReferencesForRemoteIds() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NodeEvent.self, configurations: configuration)
        let context = ModelContext(container)
        let tree = NodeTree()
        let store = EventStore(modelContext: context, nodeTree: tree)
        let undoManager = TalkToDoFeature.UndoManager()
        let executor = OperationExecutor(eventStore: store, undoManager: undoManager)

        let operations: [TalkToDoFeature.Operation] = [
            TalkToDoFeature.Operation(type: "insertNode", nodeId: "parent", title: "Buy stuff from DMart", parentId: nil, position: 0),
            TalkToDoFeature.Operation(type: "insertNode", nodeId: "milk", title: "Milk", parentId: "parent", position: 0),
            TalkToDoFeature.Operation(type: "insertNode", nodeId: "eggs", title: "Eggs", parentId: "parent", position: 1),
            TalkToDoFeature.Operation(type: "insertNode", nodeId: "spinach", title: "Spinach", parentId: "parent", position: 2)
        ]

        _ = try executor.execute(operations: operations)

        XCTAssertEqual(tree.rootNodes.count, 1)
        let root = tree.rootNodes[0]
        XCTAssertEqual(root.title, "Buy stuff from DMart")
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.children.map(\.title), ["Milk", "Eggs", "Spinach"])
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
