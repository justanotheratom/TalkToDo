import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct NodeRow: View {
    let node: Node
    let depth: Int
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    public init(
        node: Node,
        depth: Int,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.node = node
        self.depth = depth
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Indentation
            if depth > 0 {
                ForEach(0..<depth, id: \.self) { _ in
                    Color.clear
                        .frame(width: 20)
                }
            }

            // Chevron indicator for collapsed nodes
            if !node.children.isEmpty {
                Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            } else {
                Color.clear
                    .frame(width: 16)
            }

            // Title
            Text(node.title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accent)
        }
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

#Preview {
    List {
        NodeRow(
            node: Node(id: "a3f2", title: "Sample Task", children: [], isCollapsed: false),
            depth: 0,
            onTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )

        NodeRow(
            node: Node(id: "b7e1", title: "Nested Task with Children", children: [
                Node(id: "c4d3", title: "Child", children: [])
            ], isCollapsed: false),
            depth: 1,
            onTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )

        NodeRow(
            node: Node(id: "f9a2", title: "Collapsed Task", children: [
                Node(id: "e8b3", title: "Hidden Child", children: [])
            ], isCollapsed: true),
            depth: 0,
            onTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )
    }
}
