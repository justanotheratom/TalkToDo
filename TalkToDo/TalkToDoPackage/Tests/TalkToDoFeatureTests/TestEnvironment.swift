import Foundation
import XCTest

enum TestEnvironment {
    @MainActor private static var envLoaded = false
    @MainActor private static var cachedGeminiKey: String?

    @MainActor
    static func loadEnv(filePath: String = #filePath) {
        guard !envLoaded else { return }
        defer { envLoaded = true }

        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let candidate = directory.appendingPathComponent(".env")
            if fileManager.fileExists(atPath: candidate.path) {
                parseEnv(at: candidate)
                break
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
    }

    @MainActor
    private static func parseEnv(at url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in contents.split(whereSeparator: \ .isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            setenv(key, value, 1)
            if key == "GEMINI_API_KEY" {
                cachedGeminiKey = value
            }
        }
    }

    @MainActor
    static func geminiAPIKey(filePath: String = #filePath) -> String? {
        loadEnv(filePath: filePath)
        if let key = cachedGeminiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
