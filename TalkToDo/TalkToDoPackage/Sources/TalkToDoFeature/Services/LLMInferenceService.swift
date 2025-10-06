import Foundation
@preconcurrency import LeapSDK
import TalkToDoShared

/// Service for LLM inference using LFM2 models
@available(iOS 18.0, macOS 15.0, *)
public actor LLMInferenceService {
    private var modelRunner: ModelRunner?
    private var currentModelURL: URL?
    private var globalConversation: Conversation?
    private var nodeContextConversation: Conversation?

    public init() {}

    // MARK: - Model Loading

    public func loadModel(at url: URL) async throws {
        // Reuse if already loaded
        if currentModelURL == url, modelRunner != nil {
            AppLogger.llm().log(event: "llm:modelAlreadyLoaded", data: ["path": url.path])
            return
        }

        // Validate model exists
        try validateModelFile(at: url)

        do {
            let runner = try await Leap.load(url: url)
            modelRunner = runner
            currentModelURL = url

            // Initialize conversations with system prompts
            let globalSystemPrompt = createSystemPrompt(nodeContext: nil)
            let systemMessage = ChatMessage(role: .system, content: [.text(globalSystemPrompt)])
            globalConversation = Conversation(
                modelRunner: runner,
                history: [systemMessage]
            )

            // We'll create node context conversation on-demand since system prompt varies
            nodeContextConversation = nil

            AppLogger.llm().log(event: "llm:modelLoaded", data: ["path": url.path])
        } catch {
            AppLogger.llm().logError(event: "llm:loadFailed", error: error, data: ["path": url.path])
            throw LLMError.loadFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        modelRunner = nil
        currentModelURL = nil
        globalConversation = nil
        nodeContextConversation = nil
        AppLogger.llm().log(event: "llm:modelUnloaded", data: [:])
    }

    // MARK: - Inference

    /// Generate operations from natural language transcript
    public func generateOperations(
        from transcript: String,
        nodeContext: NodeContext?
    ) async throws -> OperationPlan {
        guard let conversation = globalConversation else {
            throw LLMError.modelNotLoaded
        }

        // For now, we only support global context (no node selection)
        // Node context would require creating a new conversation each time
        // since the system prompt changes based on selected node
        if nodeContext != nil {
            AppLogger.llm().log(event: "llm:nodeContextIgnored", data: [
                "reason": "not implemented - would break conversation reuse"
            ])
        }

        let message = ChatMessage(role: .user, content: [.text(transcript)])

        var fullResponse = ""
        do {
            for try await response in conversation.generateResponse(message: message) {
                try Task.checkCancellation()

                switch response {
                case .chunk(let text):
                    fullResponse += text
                case .complete(_, _):
                    break
                default:
                    continue
                }
            }
        } catch {
            AppLogger.llm().logError(event: "llm:generationFailed", error: error)
            throw LLMError.generationFailed(error.localizedDescription)
        }

        // Extract and parse JSON response
        let cleanedJSON = extractJSON(from: fullResponse)

        do {
            let jsonData = cleanedJSON.data(using: .utf8) ?? Data()
            let plan = try JSONDecoder().decode(OperationPlan.self, from: jsonData)
            AppLogger.llm().log(event: "llm:operationsParsed", data: [
                "operationCount": plan.operations.count,
                "response": cleanedJSON
            ])
            return plan
        } catch {
            AppLogger.llm().logError(event: "llm:jsonParseFailed", error: error, data: [
                "response": fullResponse
            ])
            throw LLMError.invalidJSONResponse(fullResponse)
        }
    }

    // MARK: - System Prompt

    private func createSystemPrompt(nodeContext: NodeContext?) -> String {
        if let context = nodeContext {
            return """
            You are a hierarchical todo list assistant. The user has selected a node and will provide a voice command.

            Selected node:
            - ID: \(context.nodeId)
            - Title: "\(context.title)"
            - Depth: \(context.depth)

            Your task: Parse the user's command and generate a JSON array of operations to execute.

            Available operations:
            - insertNode: Add new node (requires nodeId, title, parentId?, position)
            - renameNode: Change node title (requires nodeId, newTitle)
            - deleteNode: Remove node (requires nodeId)
            - reparentNode: Move node (requires nodeId, newParentId?, newPosition)

            Rules:
            - Use 4-character hex IDs (e.g., "a3f2") for new nodes
            - Reference the selected node using ID "\(context.nodeId)"
            - Interpret commands relative to the selected node
            - Return only valid JSON matching this schema:

            {
              "operations": [
                {
                  "type": "insertNode",
                  "nodeId": "a3f2",
                  "title": "Node title",
                  "parentId": "\(context.nodeId)",
                  "position": 0
                }
              ]
            }

            Examples:
            - "Add buy milk" → Insert child under selected node
            - "Rename to Shopping" → Rename selected node
            - "Delete this" → Delete selected node
            """
        } else {
            return """
            Convert speech to todo list operations. Return ONLY valid JSON, no explanations.

            CRITICAL RULES:
            1. Your response must be ONLY the JSON object. No text before or after.
            2. The "type" field MUST ALWAYS be "insertNode" - NEVER create custom types
            3. The user's speech becomes the "title" field - do NOT interpret it as an operation type
            4. Generate unique 4-character lowercase hex IDs (e.g., "a3f2", "b7e1") for each node
            5. Use parentId: null for root level items
            6. Position is 0-based index in parent's children
            7. Keep titles concise (under 50 chars)
            8. Create flat lists unless hierarchy is explicit (e.g., "Project X: task A, task B")

            Required JSON schema (type is ALWAYS "insertNode"):
            {
              "operations": [
                {
                  "type": "insertNode",
                  "nodeId": "a3f2",
                  "title": "Task title here",
                  "parentId": null,
                  "position": 0
                }
              ]
            }

            Examples showing type is ALWAYS "insertNode":

            Input: "Buy milk and cookies"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "a1b2", "title": "Buy milk", "parentId": null, "position": 0},
                {"type": "insertNode", "nodeId": "c3d4", "title": "Buy cookies", "parentId": null, "position": 1}
              ]
            }

            Input: "I need to pick up my car from the body shop"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "e5f6", "title": "Pick up car from body shop", "parentId": null, "position": 0}
              ]
            }

            Input: "Weekend plans: hiking Saturday, movie Sunday"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "a7b8", "title": "Weekend plans", "parentId": null, "position": 0},
                {"type": "insertNode", "nodeId": "c9d0", "title": "Hiking Saturday", "parentId": "a7b8", "position": 0},
                {"type": "insertNode", "nodeId": "e1f2", "title": "Movie Sunday", "parentId": "a7b8", "position": 1}
              ]
            }

            REMEMBER: type is ALWAYS "insertNode". Return ONLY the JSON object.
            """
        }
    }

    // MARK: - Helpers

    /// Extract JSON object from response, removing any surrounding text
    private func extractJSON(from response: String) -> String {
        // Trim whitespace
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it already starts with {, try to find the matching closing brace
        if trimmed.hasPrefix("{") {
            var braceCount = 0
            var inString = false
            var escapeNext = false

            for (index, char) in trimmed.enumerated() {
                if escapeNext {
                    escapeNext = false
                    continue
                }

                if char == "\\" {
                    escapeNext = true
                    continue
                }

                if char == "\"" && !escapeNext {
                    inString.toggle()
                    continue
                }

                if !inString {
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            // Found matching closing brace
                            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: index + 1)
                            return String(trimmed[..<endIndex])
                        }
                    }
                }
            }
        }

        // Fallback: return original if no extraction worked
        return trimmed
    }

    private func validateModelFile(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            AppLogger.llm().log(event: "llm:validateFailed", data: [
                "reason": "fileNotExists",
                "path": url.path
            ])
            throw LLMError.modelNotFound(url.path)
        }

        if isDir.boolValue {
            let contents = try fm.contentsOfDirectory(atPath: url.path)
            AppLogger.llm().log(event: "llm:validateDir", data: [
                "path": url.path,
                "contentCount": contents.count
            ])
            guard !contents.isEmpty else {
                AppLogger.llm().log(event: "llm:validateFailed", data: [
                    "reason": "emptyDirectory",
                    "path": url.path
                ])
                throw LLMError.modelNotFound(url.path)
            }
        } else {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            AppLogger.llm().log(event: "llm:validateFile", data: [
                "path": url.path,
                "fileSize": fileSize
            ])
            guard fileSize > 1024 else {
                AppLogger.llm().log(event: "llm:validateFailed", data: [
                    "reason": "fileTooSmall",
                    "path": url.path,
                    "fileSize": fileSize
                ])
                throw LLMError.modelNotFound(url.path)
            }
        }
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, macOS 15.0, *)
public struct NodeContext: Sendable {
    public let nodeId: String
    public let title: String
    public let depth: Int

    public init(nodeId: String, title: String, depth: Int) {
        self.nodeId = nodeId
        self.title = title
        self.depth = depth
    }
}

public enum LLMError: Error, LocalizedError {
    case modelNotLoaded
    case modelNotFound(String)
    case loadFailed(String)
    case generationFailed(String)
    case invalidJSONResponse(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded. Please load a model first."
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .loadFailed(let message):
            return "Failed to load model: \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .invalidJSONResponse(let response):
            return "Failed to parse LLM response as JSON. Response: \(response.prefix(200))"
        }
    }
}
