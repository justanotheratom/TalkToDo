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
            _ = try await client.submitTask(audioURL: nil, transcript: "hello", localeIdentifier: nil, eventLog: [], nodeSnapshot: [])
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
            _ = try await client.submitTask(audioURL: URL(fileURLWithPath: "/tmp/does-not-exist.caf"), transcript: "hi", localeIdentifier: nil, eventLog: [], nodeSnapshot: [])
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

        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        let result = try await pipeline.process(text: "type text", context: context)
        XCTAssertEqual(result.transcript, "remote")
        XCTAssertNil(client.capturedAudioURL)
        XCTAssertEqual(client.capturedTranscript, "type text")
    }

    func testGeminiPipelinePropagatesClientError() async {
        let client = StubGeminiClient(result: .failure(GeminiAPIClient.ClientError.invalidResponse))
        let pipeline = GeminiTextPipeline(client: client)

        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        do {
            _ = try await pipeline.process(text: "hi", context: context)
            XCTFail("Expected invalid response error")
        } catch let error as GeminiAPIClient.ClientError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testEventLogSinceLaunchReturnsLatestTwentyEntries() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NodeEvent.self, configurations: configuration)
        let context = ModelContext(container)
        let tree = NodeTree()
        let store = EventStore(modelContext: context, nodeTree: tree)

        let encoder = JSONEncoder()
        let baseDate = Date()
        var nodeIds: [String] = []

        for index in 0..<25 {
            let nodeId = String(format: "%04x", index)
            nodeIds.append(nodeId)
            let payload = InsertNodePayload(nodeId: nodeId, title: "Task \(index)", parentId: nil, position: 0)
            let payloadData = try encoder.encode(payload)
            let event = NodeEvent(
                timestamp: baseDate.addingTimeInterval(Double(index)),
                type: .insertNode,
                payload: payloadData,
                batchId: NodeID.generateBatchID()
            )
            try store.appendEvent(event)
        }

        let history = try store.eventLogSinceLaunch()
        XCTAssertEqual(history.count, 20)
        let expectedIds = Array(nodeIds.suffix(20))
        XCTAssertEqual(history.compactMap { $0.nodeId }, expectedIds)
    }

    func testGeminiPipelinePassesEventLogHistory() async throws {
        let entries: [EventLogEntry] = (0..<3).map { index in
            EventLogEntry(
                timestamp: Date().addingTimeInterval(Double(index)),
                type: .insertNode,
                nodeId: String(format: "%04x", index),
                title: "Task \(index)",
                parentId: nil,
                position: index,
                newTitle: nil,
                newParentId: nil,
                newPosition: nil
            )
        }

        let response = GeminiStructuredResponse(transcript: "done", operations: [])
        let client = StubGeminiClient(result: .success(response))
        let pipeline = GeminiTextPipeline(client: client)
        let context = ProcessingContext(nodeContext: nil, eventLog: entries, nodeSnapshot: [])

        _ = try await pipeline.process(text: "Hello", context: context)
        XCTAssertEqual(client.capturedEventLogCount, entries.count)
    }

    @MainActor
    func testGeminiPipelineUsesEventLogForMultiTurnCommands() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NodeEvent.self, configurations: configuration)
        let context = ModelContext(container)
        let tree = NodeTree()
        let store = EventStore(modelContext: context, nodeTree: tree)

        let encoder = JSONEncoder()
        let insertPayload = InsertNodePayload(nodeId: "a001", title: "Get a haircut", parentId: nil, position: 0)
        let insertData = try encoder.encode(insertPayload)
        let initialEvent = NodeEvent(
            timestamp: Date(),
            type: .insertNode,
            payload: insertData,
            batchId: NodeID.generateBatchID()
        )
        try store.appendEvent(initialEvent)
        XCTAssertEqual(tree.rootNodes.count, 1)

        let response = GeminiStructuredResponse(
            transcript: "done",
            operations: [
                TalkToDoFeature.Operation(
                    type: "deleteNode",
                    nodeId: insertPayload.nodeId,
                    title: nil,
                    parentId: nil,
                    position: nil
                )
            ]
        )

        let client = StubGeminiClient(result: .success(response))
        let pipeline = GeminiTextPipeline(client: client)
        let coordinator = TextInputCoordinator(
            eventStore: store,
            pipeline: AnyTextProcessingPipeline(pipeline),
            mode: .remoteGemini,
            undoManager: TalkToDoFeature.UndoManager()
        )

        await coordinator.processText("Mark it as done")

        XCTAssertEqual(client.capturedEventLog.count, 1)
        XCTAssertEqual(client.capturedEventLog.first?.nodeId, insertPayload.nodeId)
        XCTAssertGreaterThan(client.capturedSnapshotCount, 0)

        let events = try store.fetchAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(tree.rootNodes.count, 0)
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
    private(set) var capturedEventLogCount: Int = 0
    private(set) var capturedEventLog: [EventLogEntry] = []
    private(set) var capturedSnapshotCount: Int = 0

    init(result: Result<GeminiStructuredResponse, Error>) {
        self.result = result
    }

    func submitTask(
        audioURL: URL?,
        transcript: String?,
        localeIdentifier: String?,
        eventLog: [EventLogEntry],
        nodeSnapshot: [SnapshotNode]
    ) async throws -> GeminiStructuredResponse {
        capturedAudioURL = audioURL
        capturedTranscript = transcript
        capturedEventLogCount = eventLog.count
        capturedEventLog = eventLog
        capturedSnapshotCount = nodeSnapshot.count
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
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        invocationCount += 1
        return result
    }
}
