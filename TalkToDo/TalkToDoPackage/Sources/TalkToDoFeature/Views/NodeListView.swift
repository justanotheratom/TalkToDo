import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct NodeListView: View {
    @Bindable var nodeTree: NodeTree
    @Bindable var store: NodeListStore

    let onToggleCollapse: (String) -> Void
    let onLongPress: (Node) -> Void
    let onLongPressRelease: () -> Void
    let onDelete: (String) -> Void
    let onEdit: (String) -> Void
    let onCheckboxToggle: (String) -> Void

    @State private var destinationNodeId: String?

    public init(
        nodeTree: NodeTree,
        store: NodeListStore,
        onToggleCollapse: @escaping (String) -> Void,
        onLongPress: @escaping (Node) -> Void,
        onLongPressRelease: @escaping () -> Void,
        onDelete: @escaping (String) -> Void,
        onEdit: @escaping (String) -> Void,
        onCheckboxToggle: @escaping (String) -> Void
    ) {
        self.nodeTree = nodeTree
        self.store = store
        self.onToggleCollapse = onToggleCollapse
        self.onLongPress = onLongPress
        self.onLongPressRelease = onLongPressRelease
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onCheckboxToggle = onCheckboxToggle
    }

    public var body: some View {
        if nodeTree.rootNodes.isEmpty {
            EmptyStateView()
        } else {
            nodeListContent
        }
    }

    private var nodeListContent: some View {
        nodeList
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(backgroundGradient)
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    visibilityToggleButton
                }
            }
#endif
            .onChange(of: nodeTree.rootNodes.count) { _, _ in
                checkForRestoredNodes()
            }
            .onChange(of: nodeTree.rootNodes.map { $0.isCompleted }) { _, _ in
                checkForRestoredNodes()
            }
            .navigationDestination(item: $destinationNodeId) { nodeId in
                if let node = nodeTree.findNode(id: nodeId) {
                    NodeDetailView(
                        parentNode: node,
                        nodeTree: nodeTree,
                        showCompleted: store.showCompleted,
                        highlightedNodes: store.highlightedNodes,
                        recordingNodeId: store.recordingNodeId,
                        selectedNodeId: store.selectedNodeId,
                        onCheckboxToggle: handleCheckboxToggle,
                        onToggleCollapse: onToggleCollapse,
                        onLongPress: onLongPress,
                        onLongPressRelease: onLongPressRelease,
                        onDelete: onDelete,
                        onEdit: onEdit
                    )
                } else {
                    missingNodeFallback()
                }
            }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.98),  // Light blue-gray
                Color(red: 0.98, green: 0.95, blue: 0.96),  // Light pink-gray
                Color(red: 0.96, green: 0.97, blue: 0.99)   // Light blue-white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var nodeList: some View {
        List {
            ForEach(visibleRootNodes, id: \.id) { node in
                nodeRow(for: node)
            }
        }
    }

    private func nodeRow(for node: Node) -> some View {
        NodeTreeRow(
            node: node,
            depth: 0,
            showCompleted: store.showCompleted,
            highlightedNodes: store.highlightedNodes,
            recordingNodeId: store.recordingNodeId,
            selectedNodeId: store.selectedNodeId,
            nodeTree: nodeTree,
            onNavigateToDetail: { destinationNodeId = $0.id },
            onCheckboxToggle: handleCheckboxToggle,
            onToggleCollapse: onToggleCollapse,
            onLongPress: onLongPress,
            onLongPressRelease: onLongPressRelease,
            onDelete: onDelete,
            onEdit: onEdit
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .opacity(store.completedNodesToRemove.contains(node.id) ? 0 : 1)
        .offset(y: store.completedNodesToRemove.contains(node.id) ? -20 : 0)
        .animation(.easeOut(duration: 1.5), value: store.completedNodesToRemove)
    }

    private var visibilityToggleButton: some View {
        Button(action: {
            store.showCompleted.toggle()
            if store.showCompleted {
                store.clearCompletedRemovals()
            }
        }) {
            Image(systemName: store.showCompleted ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(store.showCompleted ? Color.accentColor : Color.secondary)
        }
    }

    private var visibleRootNodes: [Node] {
        let filtered = store.showCompleted
            ? nodeTree.rootNodes
            : nodeTree.rootNodes.filter { !$0.isCompleted }

        return filtered
            .filter { !$0.isDeleted }  // Filter out deleted nodes
            .filter { !store.completedNodesToRemove.contains($0.id) }
    }

    @ViewBuilder
    private func missingNodeFallback() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("That item is no longer available.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func handleCheckboxToggle(_ nodeId: String) {
        // Check state BEFORE toggle
        let wasCompleted = nodeTree.rootNodes.first(where: { $0.id == nodeId })?.isCompleted ?? false

        onCheckboxToggle(nodeId)

        // Only schedule removal if this is a root node being completed (was not completed before)
        if let node = nodeTree.rootNodes.first(where: { $0.id == nodeId }) {
            if node.isCompleted && !wasCompleted {
                // Just got completed - schedule fade-out
                store.scheduleRemoval(of: nodeId)
            } else if !node.isCompleted && wasCompleted {
                // Just got unchecked - restore immediately
                store.restoreNode(nodeId)
            }
        }
    }

    private func checkForRestoredNodes() {
        // Check if any nodes in removal set got uncompleted (e.g., via undo)
        for nodeId in store.completedNodesToRemove {
            if let node = nodeTree.rootNodes.first(where: { $0.id == nodeId }),
               !node.isCompleted {
                store.restoreNode(nodeId)
            }
        }
    }
}

#Preview("NodeListView") {
    @Previewable @State var tree = NodeTree()
    @Previewable @State var store = NodeListStore()

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

    return NavigationStack {
        NodeListView(
            nodeTree: tree,
            store: store,
            onToggleCollapse: { _ in },
            onLongPress: { _ in },
            onLongPressRelease: { },
            onDelete: { _ in },
            onEdit: { _ in },
            onCheckboxToggle: { _ in }
        )
        .navigationTitle("TalkToDo")
    }
}
