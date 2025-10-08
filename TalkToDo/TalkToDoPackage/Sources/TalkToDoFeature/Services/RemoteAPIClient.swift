import Foundation
import TalkToDoShared

public protocol RemoteAPIClientProtocol: Sendable {
    func submitTask(
        audioURL: URL?,
        transcript: String?,
        localeIdentifier: String?,
        eventLog: [EventLogEntry],
        nodeSnapshot: [SnapshotNode]
    ) async throws -> RemoteStructuredResponse
}

public struct RemoteAPIClient: RemoteAPIClientProtocol {
    public struct Configuration: Sendable {
        public let modelConfig: ModelConfig
        public let systemPrompt: String
        public let apiKey: String

        public init(modelConfig: ModelConfig, systemPrompt: String, apiKey: String) {
            self.modelConfig = modelConfig
            self.systemPrompt = systemPrompt
            self.apiKey = apiKey
        }
    }

    public enum ClientError: Error, LocalizedError, Equatable {
        case missingAPIKey
        case missingAudioFile
        case serializationFailed
        case invalidResponse
        case httpError(code: Int, message: String?)
        case emptyContent
        case invalidJSON

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key is missing."
            case .missingAudioFile:
                return "No audio file was provided for processing."
            case .serializationFailed:
                return "Failed to serialize request payload."
            case .invalidResponse:
                return "Received an invalid response from the API."
            case .httpError(let code, let message):
                let prefix = "API request failed with status \(code)"
                if let message, !message.isEmpty {
                    return "\(prefix): \(message)"
                }
                return prefix
            case .emptyContent:
                return "API response did not contain any content to parse."
            case .invalidJSON:
                return "API response did not include valid JSON operations."
            }
        }
    }

    private let configuration: Configuration
    private let urlSession: URLSession

    public init(configuration: Configuration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func submitTask(
        audioURL: URL?,
        transcript: String?,
        localeIdentifier: String?,
        eventLog: [EventLogEntry],
        nodeSnapshot: [SnapshotNode]
    ) async throws -> RemoteStructuredResponse {
        guard !configuration.apiKey.isEmpty else {
            throw ClientError.missingAPIKey
        }

        var userContent: [[String: Any]] = []

        if !eventLog.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let logString: String
            if let data = try? encoder.encode(eventLog),
               let json = String(data: data, encoding: .utf8) {
                logString = json
            } else {
                logString = "[]"
            }

            userContent.append([
                "type": "text",
                "text": "Event log since app start (JSON array): \(logString)"
            ])
        }

        if !nodeSnapshot.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let snapshotString: String
            if let data = try? encoder.encode(nodeSnapshot),
               let json = String(data: data, encoding: .utf8) {
                snapshotString = json
            } else {
                snapshotString = "[]"
            }

            userContent.append([
                "type": "text",
                "text": "Current todo tree snapshot (JSON array): \(snapshotString)"
            ])
        }

        if let audioURL {
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw ClientError.missingAudioFile
            }

            let audioData = try Data(contentsOf: audioURL)
            let base64Audio = audioData.base64EncodedString()
            let audioFormat = audioURL.pathExtension.lowercased().isEmpty ? "wav" : audioURL.pathExtension.lowercased()

            userContent.append([
                "type": "input_audio",
                "input_audio": [
                    "format": audioFormat,
                    "data": base64Audio
                ]
            ])
        }

        if let transcript, !transcript.isEmpty {
            userContent.append([
                "type": "text",
                "text": transcript
            ])
        }

        guard !userContent.isEmpty else {
            throw ClientError.serializationFailed
        }

        var systemPrompt = configuration.systemPrompt
        if let localeIdentifier {
            systemPrompt += " User locale: \(localeIdentifier)."
        }

        let body: [String: Any] = [
            "model": configuration.modelConfig.modelIdentifier,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": [
                        [
                            "type": "text",
                            "text": systemPrompt
                        ]
                    ]
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(body),
              let httpBody = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw ClientError.serializationFailed
        }

        var request = URLRequest(url: configuration.modelConfig.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = httpBody
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw ClientError.httpError(code: httpResponse.statusCode, message: message)
        }

        let completion = try JSONDecoder().decode(GeminiChatCompletion.self, from: data)
        guard let contentText = completion.primaryText else {
            throw ClientError.emptyContent
        }

        let jsonFragment = contentText.extractJSONBlock()
        guard let jsonData = jsonFragment.data(using: .utf8) else {
            throw ClientError.invalidJSON
        }

        let plan = try JSONDecoder().decode(OperationPlan.self, from: jsonData)
        return RemoteStructuredResponse(
            transcript: transcript,
            operations: plan.operations
        )
    }
}

private struct GeminiChatCompletion: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let contents: [Content]?
        let contentString: String?

        enum CodingKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let array = try? container.decode([Content].self, forKey: .content) {
                contents = array
                contentString = nil
            } else if let string = try? container.decode(String.self, forKey: .content) {
                contents = nil
                contentString = string
            } else {
                contents = nil
                contentString = nil
            }
        }
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }

    let choices: [Choice]

    var primaryText: String? {
        for choice in choices {
            if let contents = choice.message.contents {
                if let match = contents.first(where: { $0.type == "text" && ($0.text?.isEmpty == false) }) {
                    return match.text
                }
            }
            if let text = choice.message.contentString, !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

private extension String {
    func extractJSONBlock() -> String {
        if let fencedRange = range(of: "```json") ?? range(of: "```JSON") {
            let remainder = self[fencedRange.upperBound...]
            if let closing = remainder.range(of: "```") {
                return String(remainder[..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let start = firstIndex(of: "{"), let end = lastIndex(of: "}") {
            return String(self[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RemoteStructuredResponse: Sendable {
    public let transcript: String?
    public let operations: [Operation]

    public init(transcript: String?, operations: [Operation]) {
        self.transcript = transcript
        self.operations = operations
    }
}
