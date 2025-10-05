import Foundation

/// A node in the hierarchical todo tree (in-memory snapshot)
public struct Node: Identifiable, Equatable {
    public let id: String  // 4-char hex
    public var title: String
    public var children: [Node]
    public var isCollapsed: Bool

    public init(id: String, title: String, children: [Node] = [], isCollapsed: Bool = false) {
        self.id = id
        self.title = title
        self.children = children
        self.isCollapsed = isCollapsed
    }

    /// Find a node by ID in the tree (depth-first search)
    public func findNode(id: String) -> Node? {
        if self.id == id {
            return self
        }
        for child in children {
            if let found = child.findNode(id: id) {
                return found
            }
        }
        return nil
    }

    /// Get the depth of this node in the tree (0 = root)
    public func depth(from root: Node) -> Int {
        if root.id == id {
            return 0
        }
        for child in root.children {
            if let childDepth = child.depth(from: child) {
                return 1 + childDepth
            }
        }
        return 0
    }
}
