import Foundation
import XCTest

enum TestEnvironment {
    @MainActor private static var envLoaded = false

    @MainActor
    static func loadEnv(filePath: String = #filePath) {
        guard !envLoaded else { return }
        defer { envLoaded = true }

        let testFileURL = URL(fileURLWithPath: filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Test file directory
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // TalkToDoPackage
            .deletingLastPathComponent() // TalkToDo

        let envURL = projectRoot.appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: envURL.path) else { return }

        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            setenv(key, value, 1)
        }
    }

    @MainActor
    static func geminiAPIKey(filePath: String = #filePath) -> String? {
        loadEnv(filePath: filePath)
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
