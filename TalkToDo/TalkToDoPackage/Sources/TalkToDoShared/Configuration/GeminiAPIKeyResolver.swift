import Foundation

public enum GeminiAPIKeySource: Sendable, Equatable {
    case environment
    case dotEnv
    case savedSettings

    public var displayName: String {
        switch self {
        case .environment:
            return "environment variable"
        case .dotEnv:
            return ".env file"
        case .savedSettings:
            return "saved settings"
        }
    }
}

public struct GeminiAPIKeyResolution: Sendable, Equatable {
    public let key: String
    public let source: GeminiAPIKeySource

    public init(key: String, source: GeminiAPIKeySource) {
        self.key = key
        self.source = source
    }
}

public enum GeminiAPIKeyResolver {
    private static let envKey = "GEMINI_API_KEY"
    private static let infoDictionaryDotEnvPathKey = "TalkToDoDotEnvPath"

    public static func resolve(
        storedKey: String?,
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> GeminiAPIKeyResolution? {
        if let environmentKey = normalize(processInfo.environment[envKey]) {
            return GeminiAPIKeyResolution(key: environmentKey, source: .environment)
        }

        if let dotEnvKey = dotEnvValue(bundle: bundle) {
            return GeminiAPIKeyResolution(key: dotEnvKey, source: .dotEnv)
        }

        if let storedKey = normalize(storedKey) {
            return GeminiAPIKeyResolution(key: storedKey, source: .savedSettings)
        }

        return nil
    }

    public static func dotEnvPath(bundle: Bundle = .main) -> String? {
        normalize(bundle.object(forInfoDictionaryKey: infoDictionaryDotEnvPathKey) as? String)
    }

    private static func dotEnvValue(bundle: Bundle) -> String? {
        guard let path = dotEnvPath(bundle: bundle),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        return value(for: envKey, in: contents)
    }

    private static func value(for key: String, in contents: String) -> String? {
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let candidate: String
            if line.hasPrefix("export ") {
                candidate = String(line.dropFirst("export ".count))
            } else {
                candidate = line
            }

            guard let separatorIndex = candidate.firstIndex(of: "=") else { continue }
            let candidateKey = String(candidate[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidateKey == key else { continue }

            let rawValue = String(candidate[candidate.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripQuotes(from: rawValue)
        }

        return nil
    }

    private static func stripQuotes(from value: String) -> String {
        guard value.count >= 2 else { return value }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }

        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }

    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
