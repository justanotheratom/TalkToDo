import SwiftUI
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct EnhancedNodeRow: View {
    @EnvironmentObject private var fontPreference: FontPreference

    let node: Node
    let depth: Int
    let highlightType: HighlightType?
    let isRecording: Bool
    let showChevron: Bool  // NEW: control whether to show our custom chevron

    let onCheckboxToggle: () -> Void
    let onNavigateInto: () -> Void
    let onTitleTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    public init(
        node: Node,
        depth: Int,
        highlightType: HighlightType? = nil,
        isRecording: Bool = false,
        showChevron: Bool = true,  // NEW: default to true for backward compatibility
        onCheckboxToggle: @escaping () -> Void,
        onNavigateInto: @escaping () -> Void,
        onTitleTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.node = node
        self.depth = depth
        self.highlightType = highlightType
        self.isRecording = isRecording
        self.showChevron = showChevron
        self.onCheckboxToggle = onCheckboxToggle
        self.onNavigateInto = onNavigateInto
        self.onTitleTap = onTitleTap
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            CheckboxView(isChecked: node.isCompleted, action: onCheckboxToggle)

            // Title
            Text(node.title)
                .font(depth == 0 ? fontPreference.selectedFont.body : fontPreference.selectedFont.subheadline)
                .foregroundStyle(node.isCompleted ? .secondary : .primary)
                .strikethrough(node.isCompleted, color: .secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !node.children.isEmpty {
                        onTitleTap()
                    }
                }

            // Chevron (only if node has children AND showChevron is true)
            if !node.children.isEmpty && showChevron {
                Button(action: onNavigateInto) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isRecording ? 2 : 0
                )
                .scaleEffect(isRecording ? 1.02 : 1.0)
                .shadow(color: Color.accentColor.opacity(isRecording ? 0.4 : 0), radius: 12, x: 0, y: 4)
                .animation(
                    isRecording
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isRecording
                )
        )
        .padding(.leading, depth > 0 ? CGFloat(depth * 24) : 0)
        .opacity(node.isCompleted ? 0.5 : 1.0)
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if let highlight = highlightType {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            highlightColor(for: highlight),
                            highlightColor(for: highlight).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: highlightColor(for: highlight).opacity(0.3), radius: 8, x: 0, y: 4)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: Color.accentColor.opacity(0.08), radius: 8, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }

    private func highlightColor(for type: HighlightType) -> Color {
        switch type {
        case .added:
            return Color.green.opacity(0.25)
        case .edited:
            return Color.orange.opacity(0.25)
        case .deleted:
            return Color.red.opacity(0.25)
        case .undone:
            return Color.blue.opacity(0.25)
        }
    }

}

#Preview {
    List {
        EnhancedNodeRow(
            node: Node(id: "a3f2", title: "Sample Task", children: [], isCompleted: false),
            depth: 0,
            onCheckboxToggle: {},
            onNavigateInto: {},
            onTitleTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )

        EnhancedNodeRow(
            node: Node(id: "b7e1", title: "Completed Task", children: [], isCompleted: true),
            depth: 0,
            highlightType: .added,
            onCheckboxToggle: {},
            onNavigateInto: {},
            onTitleTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )

        EnhancedNodeRow(
            node: Node(id: "c4d3", title: "Recording...", children: [], isCompleted: false),
            depth: 0,
            isRecording: true,
            onCheckboxToggle: {},
            onNavigateInto: {},
            onTitleTap: {},
            onLongPress: {},
            onDelete: {},
            onEdit: {}
        )
    }
    .listStyle(.plain)
}
