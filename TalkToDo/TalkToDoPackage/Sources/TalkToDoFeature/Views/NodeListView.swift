import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct NodeListView: View {
    @Bindable var nodeTree: NodeTree
    let onToggleCollapse: (String) -> Void
    let onLongPress: (Node) -> Void
    let onDelete: (String) -> Void
    let onEdit: (String) -> Void

    public init(
        nodeTree: NodeTree,
        onToggleCollapse: @escaping (String) -> Void,
        onLongPress: @escaping (Node) -> Void,
        onDelete: @escaping (String) -> Void,
        onEdit: @escaping (String) -> Void
    ) {
        self.nodeTree = nodeTree
        self.onToggleCollapse = onToggleCollapse
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    public var body: some View {
        if nodeTree.rootNodes.isEmpty {
            EmptyStateView()
        } else {
            List {
                ForEach(nodeTree.rootNodes, id: \.id) { node in
                    NodeTreeRow(
                        node: node,
                        depth: 0,
                        onToggleCollapse: onToggleCollapse,
                        onLongPress: onLongPress,
                        onDelete: onDelete,
                        onEdit: onEdit
                    )
                }
            }
            .listStyle(.plain)
        }
    }
}

/// Recursive row that renders a node and its children
@available(iOS 18.0, macOS 15.0, *)
private struct NodeTreeRow: View {
    let node: Node
    let depth: Int
    let onToggleCollapse: (String) -> Void
    let onLongPress: (Node) -> Void
    let onDelete: (String) -> Void
    let onEdit: (String) -> Void

    var body: some View {
        Group {
            NodeRow(
                node: node,
                depth: depth,
                onTap: {
                    if !node.children.isEmpty {
                        onToggleCollapse(node.id)
                    }
                },
                onLongPress: {
                    onLongPress(node)
                },
                onDelete: {
                    onDelete(node.id)
                },
                onEdit: {
                    onEdit(node.id)
                }
            )

            // Render children if not collapsed
            if !node.isCollapsed {
                ForEach(node.children, id: \.id) { child in
                    NodeTreeRow(
                        node: child,
                        depth: depth + 1,
                        onToggleCollapse: onToggleCollapse,
                        onLongPress: onLongPress,
                        onDelete: onDelete,
                        onEdit: onEdit
                    )
                }
            }
        }
    }
}

#Preview {
    let tree = NodeTree()
    let root1 = Node(id: "a3f2", title: "Thanksgiving Prep", children: [
        Node(id: "b7e1", title: "Groceries", children: [
            Node(id: "c4d3", title: "turkey"),
            Node(id: "d8f5", title: "cranberries")
        ]),
        Node(id: "e9a2", title: "House", children: [
            Node(id: "f1b6", title: "clean guest room")
        ])
    ])
    tree.rootNodes = [root1]

    return NodeListView(
        nodeTree: tree,
        onToggleCollapse: { _ in },
        onLongPress: { _ in },
        onDelete: { _ in },
        onEdit: { _ in }
    )
}
