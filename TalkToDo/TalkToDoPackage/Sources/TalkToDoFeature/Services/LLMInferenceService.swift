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
        nodeContext: NodeContext?,
        retryCount: Int = 0
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

            // Validate parent references
            let validationError = validateParentReferences(operations: plan.operations)
            if let error = validationError {
                AppLogger.llm().log(event: "llm:validationFailed", data: [
                    "error": error,
                    "retryCount": retryCount
                ])

                // Retry once with feedback
                if retryCount < 1 {
                    let feedbackMessage = """
                    ERROR: Your JSON has invalid parent references. \(error)

                    REMEMBER: You can ONLY use a nodeId as parentId if that exact nodeId was created in an EARLIER operation in the array. Parent nodes must come FIRST.

                    Please regenerate the COMPLETE JSON with all operations, fixing the parent references.
                    """

                    AppLogger.llm().log(event: "llm:retryingWithFeedback", data: [
                        "feedback": feedbackMessage
                    ])

                    return try await generateOperations(
                        from: feedbackMessage,
                        nodeContext: nodeContext,
                        retryCount: retryCount + 1
                    )
                } else {
                    AppLogger.llm().log(event: "llm:validationFailedAfterRetry", data: [
                        "response": cleanedJSON
                    ])
                    // Continue with invalid plan - VoiceInputCoordinator will fix it
                }
            }

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

    /// Validate that all parent IDs reference earlier operations
    private func validateParentReferences(operations: [Operation]) -> String? {
        var createdIds = Set<String>()
        var invalidRefs: [(nodeId: String, parentId: String)] = []

        for operation in operations {
            if let parentId = operation.parentId, !createdIds.contains(parentId) {
                invalidRefs.append((operation.nodeId, parentId))
            }
            createdIds.insert(operation.nodeId)
        }

        if !invalidRefs.isEmpty {
            let examples = invalidRefs.prefix(3).map { "nodeId '\($0.nodeId)' references non-existent parentId '\($0.parentId)'" }.joined(separator: "; ")
            return "Found \(invalidRefs.count) invalid parent reference(s): \(examples)"
        }

        return nil
    }

    // MARK: - System Prompt

    private func createSystemPrompt(nodeContext: NodeContext?) -> String {
        if let context = nodeContext {
            let parentInfo = if let parentId = context.parentId, let parentTitle = context.parentTitle {
                """

                Parent node:
                - ID: \(parentId)
                - Title: "\(parentTitle)"
                """
            } else {
                ""
            }

            return """
            You are a hierarchical todo list assistant. The user has selected a node and will provide a voice command.

            Selected node:
            - ID: \(context.nodeId)
            - Title: "\(context.title)"
            - Depth: \(context.depth)\(parentInfo)

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
            2. EVERY operation MUST have ALL 5 fields: type, nodeId, title, parentId, position
            3. The "type" field MUST ALWAYS be "insertNode" - NEVER create custom types
            4. The user's speech becomes the "title" field - do NOT interpret it as an operation type
            5. Generate unique 4-character lowercase hex IDs (e.g., "a3f2", "b7e1") for each node
            6. Position is 0-based index (0, 1, 2, 3...)
            7. Keep titles concise (under 50 chars)
            8. Detect hierarchy patterns:
               - "X and Y and Z" → flat list (3 separate root items)
               - "Buy/Get X, Y, Z from PLACE" → parent "Buy/Get from PLACE" with children X, Y, Z
               - "Do X: A, B, C" → parent "Do X" with children A, B, C
               - Just a single action → one root item
            9. IMPORTANT: When creating hierarchies, the parent node MUST be the FIRST operation in the array
            10. CRITICAL: You can ONLY use a nodeId as parentId if that nodeId was already created in an EARLIER operation
            11. NEVER invent parent IDs - if you reference a parentId, that exact nodeId must appear earlier in the operations array
            12. DO NOT add explanatory comments or extra fields - just the required 5 fields per operation

            Required JSON schema - ALL 5 fields are REQUIRED for EVERY operation:
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

            Examples:

            Input: "Call dentist and schedule haircut and pay rent"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "a1b2", "title": "Call dentist", "parentId": null, "position": 0},
                {"type": "insertNode", "nodeId": "c3d4", "title": "Schedule haircut", "parentId": null, "position": 1},
                {"type": "insertNode", "nodeId": "e5f6", "title": "Pay rent", "parentId": null, "position": 2}
              ]
            }

            Input: "Buy milk eggs butter and lemon from the supermarket"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "p1a2", "title": "Buy from the supermarket", "parentId": null, "position": 0},
                {"type": "insertNode", "nodeId": "c1b2", "title": "Milk", "parentId": "p1a2", "position": 0},
                {"type": "insertNode", "nodeId": "c3d4", "title": "Eggs", "parentId": "p1a2", "position": 1},
                {"type": "insertNode", "nodeId": "c5e6", "title": "Butter", "parentId": "p1a2", "position": 2},
                {"type": "insertNode", "nodeId": "c7f8", "title": "Lemon", "parentId": "p1a2", "position": 3}
              ]
            }

            Input: "I need to pick up my car from the body shop"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "c5d6", "title": "Pick up car from body shop", "parentId": null, "position": 0}
              ]
            }

            Input: "Pack list for the trip: shoes socks clothes toiletries"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "p1a2", "title": "Pack list for the trip", "parentId": null, "position": 0},
                {"type": "insertNode", "nodeId": "s3b4", "title": "Shoes", "parentId": "p1a2", "position": 0},
                {"type": "insertNode", "nodeId": "s5c6", "title": "Socks", "parentId": "p1a2", "position": 1},
                {"type": "insertNode", "nodeId": "c7d8", "title": "Clothes", "parentId": "p1a2", "position": 2},
                {"type": "insertNode", "nodeId": "t9e0", "title": "Toiletries", "parentId": "p1a2", "position": 3}
              ]
            }

            Input: "I need to go get a haircut"
            Output:
            {
              "operations": [
                {"type": "insertNode", "nodeId": "h1a2", "title": "Get a haircut", "parentId": null, "position": 0}
              ]
            }

            REMEMBER: ALL 5 fields required (type, nodeId, title, parentId, position). Type is ALWAYS "insertNode". Return ONLY the JSON object.
            """
        }
    }

    // MARK: - Helpers

    /// Extract JSON object from response, removing any surrounding text
    private func extractJSON(from response: String) -> String {
        // Trim whitespace
        var trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present (e.g., ```json ... ```)
        if trimmed.hasPrefix("```") {
            // Remove opening fence
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            // Remove closing fence
            if trimmed.hasSuffix("```") {
                trimmed = String(trimmed.dropLast(3))
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

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
    public let parentId: String?
    public let parentTitle: String?

    public init(nodeId: String, title: String, depth: Int, parentId: String? = nil, parentTitle: String? = nil) {
        self.nodeId = nodeId
        self.title = title
        self.depth = depth
        self.parentId = parentId
        self.parentTitle = parentTitle
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
