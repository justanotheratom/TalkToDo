import Foundation

/// LLM-generated operation plan (structured output from LFM2)
@available(iOS 18.0, macOS 15.0, *)
public struct OperationPlan: Codable {
    public let operations: [Operation]

    public init(operations: [Operation]) {
        self.operations = operations
    }
}

/// Single node operation from LLM
@available(iOS 18.0, macOS 15.0, *)
public struct Operation: Codable {
    public let type: String
    public let nodeId: String
    public let title: String?
    public let parentId: String?
    public let position: Int?

    public init(
        type: String,
        nodeId: String,
        title: String? = nil,
        parentId: String? = nil,
        position: Int? = nil
    ) {
        self.type = type
        self.nodeId = nodeId
        self.title = title
        self.parentId = parentId
        self.position = position
    }

    public enum OperationType: String {
        case insertNode
        case renameNode
        case deleteNode
        case reparentNode
    }

    public var operationType: OperationType? {
        OperationType(rawValue: type)
    }
}
