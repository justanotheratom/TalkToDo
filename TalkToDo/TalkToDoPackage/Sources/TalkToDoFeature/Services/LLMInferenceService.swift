import Foundation
@preconcurrency import LeapSDK
import TalkToDoShared

/// Service for LLM inference using LFM2 models
@available(iOS 18.0, macOS 15.0, *)
public actor LLMInferenceService {
    private var modelRunner: ModelRunner?
    private var currentModelURL: URL?

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
            AppLogger.llm().log(event: "llm:modelLoaded", data: ["path": url.path])
        } catch {
            AppLogger.llm().logError(event: "llm:loadFailed", error: error, data: ["path": url.path])
            throw LLMError.loadFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        modelRunner = nil
        currentModelURL = nil
        AppLogger.llm().log(event: "llm:modelUnloaded", data: [:])
    }

    // MARK: - Inference

    /// Generate operations from natural language transcript
    public func generateOperations(
        from transcript: String,
        nodeContext: NodeContext?
    ) async throws -> OperationPlan {
        guard let runner = modelRunner else {
            throw LLMError.modelNotLoaded
        }

        let systemPrompt = createSystemPrompt(nodeContext: nodeContext)
        let userPrompt = transcript

        let conversation = Conversation(
            modelRunner: runner,
            systemPrompt: systemPrompt
        )

        let message = ChatMessage(role: .user, content: [.text(userPrompt)])

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

        // Parse JSON response
        do {
            let jsonData = fullResponse.data(using: .utf8) ?? Data()
            let plan = try JSONDecoder().decode(OperationPlan.self, from: jsonData)
            AppLogger.llm().log(event: "llm:operationsParsed", data: [
                "operationCount": plan.operations.count
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
            You are a hierarchical todo list assistant. Parse natural speech into structured todo operations.

            Your task: Extract hierarchy from the user's speech and generate a JSON array of node operations.

            Hierarchy extraction:
            - Pauses indicate new items
            - "Then", "also", "and" indicate siblings
            - Indentation/nesting is implied by context (e.g., "Groceries: milk, bread")
            - When in doubt, create a flat list

            Available operations:
            - insertNode: Add new node (requires nodeId, title, parentId?, position)

            Rules:
            - Use 4-character hex IDs (e.g., "a3f2", "b7e1") for all new nodes
            - parentId = null means root level
            - position = index in parent's children (0-based)
            - Return only valid JSON matching this schema:

            {
              "operations": [
                {
                  "type": "insertNode",
                  "nodeId": "a3f2",
                  "title": "Groceries",
                  "parentId": null,
                  "position": 0
                },
                {
                  "type": "insertNode",
                  "nodeId": "b7e1",
                  "title": "milk",
                  "parentId": "a3f2",
                  "position": 0
                }
              ]
            }

            Example: "Thanksgiving prep... groceries: turkey, cranberries... house: clean guest room"
            → Creates parent "Thanksgiving prep" with two children "groceries" and "house", each with their own children
            """
        }
    }

    // MARK: - Helpers

    private func validateModelFile(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw LLMError.modelNotFound(url.path)
        }

        if isDir.boolValue {
            let contents = try fm.contentsOfDirectory(atPath: url.path)
            guard !contents.isEmpty else {
                throw LLMError.modelNotFound(url.path)
            }
        } else {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            guard fileSize > 1024 else {
                throw LLMError.modelNotFound(url.path)
            }
        }
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, macOS 15.0, *)
public struct NodeContext {
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
