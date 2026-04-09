import Foundation
import TalkToDoShared

public struct UITestTextPipeline: TextProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case emptyText

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Please enter some text to convert into tasks."
            }
        }
    }

    public init() {}

    public func process(
        text: String,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PipelineError.emptyText
        }

        return OperationGenerationResult(
            transcript: trimmed,
            operations: UITestOperationParser.operations(for: trimmed, context: context)
        )
    }
}

public struct UITestVoicePipeline: VoiceProcessingPipeline {
    public enum PipelineError: Error, LocalizedError {
        case missingTranscript

        public var errorDescription: String? {
            switch self {
            case .missingTranscript:
                return "No transcript available for UI test processing."
            }
        }
    }

    public init() {}

    public func process(
        metadata: RecordingMetadata,
        context: ProcessingContext
    ) async throws -> OperationGenerationResult {
        guard let transcript = metadata.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            throw PipelineError.missingTranscript
        }

        return OperationGenerationResult(
            transcript: transcript,
            operations: UITestOperationParser.operations(for: transcript, context: context)
        )
    }
}

private enum UITestOperationParser {
    static func operations(for rawInput: String, context: ProcessingContext) -> [Operation] {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let insertionParentId = context.nodeContext?.nodeId

        if let hierarchy = parseHierarchy(from: input) {
            return makeHierarchyOperations(
                parentTitle: hierarchy.parent,
                childTitles: hierarchy.children,
                insertionParentId: insertionParentId,
                context: context
            )
        }

        let siblingItems = input
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if siblingItems.count > 1 {
            return makeSiblingOperations(
                titles: siblingItems,
                parentId: insertionParentId,
                context: context
            )
        }

        return makeSiblingOperations(
            titles: [input],
            parentId: insertionParentId,
            context: context
        )
    }

    private static func parseHierarchy(from input: String) -> (parent: String, children: [String])? {
        let separators = [":", ">", "->"]

        for separator in separators {
            guard let range = input.range(of: separator) else { continue }

            let parent = input[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let children = input[range.upperBound...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !parent.isEmpty, !children.isEmpty {
                return (parent, children)
            }
        }

        return nil
    }

    private static func makeHierarchyOperations(
        parentTitle: String,
        childTitles: [String],
        insertionParentId: String?,
        context: ProcessingContext
    ) -> [Operation] {
        let parentId = NodeID.generate()
        let parentPosition = nextPosition(parentId: insertionParentId, snapshot: context.nodeSnapshot)

        var operations = [
            Operation(
                type: Operation.OperationType.insertNode.rawValue,
                nodeId: parentId,
                title: parentTitle,
                parentId: insertionParentId,
                position: parentPosition
            )
        ]

        for (index, childTitle) in childTitles.enumerated() {
            operations.append(
                Operation(
                    type: Operation.OperationType.insertNode.rawValue,
                    nodeId: NodeID.generate(),
                    title: childTitle,
                    parentId: parentId,
                    position: index
                )
            )
        }

        return operations
    }

    private static func makeSiblingOperations(
        titles: [String],
        parentId: String?,
        context: ProcessingContext
    ) -> [Operation] {
        let startPosition = nextPosition(parentId: parentId, snapshot: context.nodeSnapshot)

        return titles.enumerated().map { index, title in
            Operation(
                type: Operation.OperationType.insertNode.rawValue,
                nodeId: NodeID.generate(),
                title: title,
                parentId: parentId,
                position: startPosition + index
            )
        }
    }

    private static func nextPosition(parentId: String?, snapshot: [SnapshotNode]) -> Int {
        guard let parentId else {
            return snapshot.count
        }

        return findNode(id: parentId, in: snapshot)?.children.count ?? 0
    }

    private static func findNode(id: String, in nodes: [SnapshotNode]) -> SnapshotNode? {
        for node in nodes {
            if node.id == id {
                return node
            }

            if let childMatch = findNode(id: id, in: node.children) {
                return childMatch
            }
        }

        return nil
    }
}
