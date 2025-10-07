import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct NodeDetailView: View {
    let parentNode: Node
    @Bindable var nodeTree: NodeTree
    let showCompleted: Bool
    let highlightedNodes: [String: HighlightType]
    let recordingNodeId: String?

    let onCheckboxToggle: (String) -> Void
    let onToggleCollapse: (String) -> Void
    let onLongPress: (Node) -> Void
    let onDelete: (String) -> Void
    let onEdit: (String) -> Void

    public init(
        parentNode: Node,
        nodeTree: NodeTree,
        showCompleted: Bool,
        highlightedNodes: [String: HighlightType],
        recordingNodeId: String?,
        onCheckboxToggle: @escaping (String) -> Void,
        onToggleCollapse: @escaping (String) -> Void,
        onLongPress: @escaping (Node) -> Void,
        onDelete: @escaping (String) -> Void,
        onEdit: @escaping (String) -> Void
    ) {
        self.parentNode = parentNode
        self.nodeTree = nodeTree
        self.showCompleted = showCompleted
        self.highlightedNodes = highlightedNodes
        self.recordingNodeId = recordingNodeId
        self.onCheckboxToggle = onCheckboxToggle
        self.onToggleCollapse = onToggleCollapse
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    public var body: some View {
        List {
            ForEach(visibleChildren, id: \.id) { child in
                NodeTreeRow(
                    node: child,
                    depth: 0,  // Reset depth for drill-down view
                    showCompleted: showCompleted,
                    highlightedNodes: highlightedNodes,
                    recordingNodeId: recordingNodeId,
                    nodeTree: nodeTree,
                    onCheckboxToggle: onCheckboxToggle,
                    onToggleCollapse: onToggleCollapse,
                    onLongPress: onLongPress,
                    onDelete: onDelete,
                    onEdit: onEdit
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(parentNode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var visibleChildren: [Node] {
        let filtered = if showCompleted {
            parentNode.children
        } else {
            parentNode.children.filter { !$0.isCompleted }
        }

        return filtered.filter { !$0.isDeleted }  // Filter out deleted nodes
    }
}

/// Recursive row that renders a node and its children
@available(iOS 18.0, macOS 15.0, *)
struct NodeTreeRow: View {
    let node: Node
    let depth: Int
    let showCompleted: Bool
    let highlightedNodes: [String: HighlightType]
    let recordingNodeId: String?
    @Bindable var nodeTree: NodeTree

    let onCheckboxToggle: (String) -> Void
    let onToggleCollapse: (String) -> Void
    let onLongPress: (Node) -> Void
    let onDelete: (String) -> Void
    let onEdit: (String) -> Void

    @State private var navigateToDetail = false

    var body: some View {
        Group {
            if node.children.isEmpty {
                // Leaf node: simple row
                EnhancedNodeRow(
                    node: node,
                    depth: depth,
                    highlightType: highlightedNodes[node.id],
                    isRecording: recordingNodeId == node.id,
                    onCheckboxToggle: { onCheckboxToggle(node.id) },
                    onNavigateInto: { },  // No navigation for leaf nodes
                    onTitleTap: { },      // No expand for leaf nodes
                    onLongPress: { onLongPress(node) },
                    onDelete: { onDelete(node.id) },
                    onEdit: { onEdit(node.id) }
                )
            } else {
                // Parent node: with navigation capability
                EnhancedNodeRow(
                    node: node,
                    depth: depth,
                    highlightType: highlightedNodes[node.id],
                    isRecording: recordingNodeId == node.id,
                    showChevron: true,
                    onCheckboxToggle: { onCheckboxToggle(node.id) },
                    onNavigateInto: { navigateToDetail = true },
                    onTitleTap: { onToggleCollapse(node.id) },
                    onLongPress: { onLongPress(node) },
                    onDelete: { onDelete(node.id) },
                    onEdit: { onEdit(node.id) }
                )
                .background(
                    NavigationLink(destination: destinationView, isActive: $navigateToDetail) {
                        EmptyView()
                    }
                    .opacity(0)
                )

                // Inline children (if expanded)
                if !node.isCollapsed {
                    ForEach(visibleChildren, id: \.id) { child in
                        NodeTreeRow(
                            node: child,
                            depth: depth + 1,
                            showCompleted: showCompleted,
                            highlightedNodes: highlightedNodes,
                            recordingNodeId: recordingNodeId,
                            nodeTree: nodeTree,
                            onCheckboxToggle: onCheckboxToggle,
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

    private var destinationView: some View {
        NodeDetailView(
            parentNode: node,
            nodeTree: nodeTree,
            showCompleted: showCompleted,
            highlightedNodes: highlightedNodes,
            recordingNodeId: recordingNodeId,
            onCheckboxToggle: onCheckboxToggle,
            onToggleCollapse: onToggleCollapse,
            onLongPress: onLongPress,
            onDelete: onDelete,
            onEdit: onEdit
        )
    }

    private var visibleChildren: [Node] {
        let filtered = if showCompleted {
            node.children
        } else {
            node.children.filter { !$0.isCompleted }
        }

        return filtered.filter { !$0.isDeleted }  // Filter out deleted nodes
    }
}
