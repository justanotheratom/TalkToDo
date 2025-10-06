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
            _ = try await client.submitTask(audioURL: URL(fileURLWithPath: "/tmp/fake.caf"), transcript: nil, localeIdentifier: nil)
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
            _ = try await client.submitTask(audioURL: URL(fileURLWithPath: "/tmp/does-not-exist.caf"), transcript: nil, localeIdentifier: nil)
            XCTFail("Expected missing audio error")
        } catch let error as GeminiAPIClient.ClientError {
            XCTAssertEqual(error, .missingAudioFile)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
