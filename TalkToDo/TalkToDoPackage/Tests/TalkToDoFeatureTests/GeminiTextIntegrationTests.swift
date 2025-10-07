import XCTest
@testable import TalkToDoFeature
@testable import TalkToDoShared

final class GeminiTextIntegrationTests: XCTestCase {
    @MainActor
    func testTextToOperationsRemoteIntegration() async throws {
        guard let apiKey = TestEnvironment.geminiAPIKey(), !apiKey.isEmpty else {
            throw XCTSkip("GEMINI_API_KEY not provided; skipping integration test")
        }

        let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!
        let client = GeminiAPIClient(configuration: .init(baseURL: baseURL, apiKey: apiKey))
        let pipeline = GeminiTextPipeline(client: client)

        let prompt = "Create a grocery todo list with milk, eggs, and bread"
        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        let result = try await pipeline.process(text: prompt, context: context)

        XCTAssertFalse(result.operations.isEmpty, "Expected Gemini to return at least one operation")
        XCTAssertFalse(result.transcript.isEmpty)
    }
}
