import SwiftUI
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct ChangelogEntryRow: View {
    @EnvironmentObject private var fontPreference: FontPreference

    let entry: ChangelogEntry

    public init(entry: ChangelogEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                Image(systemName: entry.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    // Description
                    Text(entry.description)
                        .font(fontPreference.selectedFont.caption)
                        .foregroundStyle(.secondary)

                    // Visual card(s)
                    cardContent

                    // Parent context (if any)
                    if let parentTitle = entry.parentTitle {
                        Text("under '\(parentTitle)'")
                            .font(fontPreference.selectedFont.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Timestamp
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(entry.formattedTimestamp)
                            .font(fontPreference.selectedFont.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch entry.type {
        case .renameNode:
            // Show before → after
            if let oldTitle = entry.oldCardTitle, let newTitle = entry.newCardTitle {
                HStack(spacing: 8) {
                    ChangelogNodeCard(title: oldTitle)
                        .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    ChangelogNodeCard(title: newTitle)
                        .frame(maxWidth: .infinity)
                }
            }

        default:
            // Show single card
            if let title = entry.cardTitle {
                ChangelogNodeCard(
                    title: title,
                    isDeleted: entry.isCardDeleted,
                    isCompleted: entry.isCardCompleted
                )
            }
        }
    }

    private var iconColor: Color {
        switch entry.iconColor {
        case "green":
            return .green
        case "orange":
            return .orange
        case "red":
            return .red
        case "blue":
            return .blue
        case "purple":
            return .purple
        case "gray":
            return .gray
        default:
            return .primary
        }
    }
}

#Preview {
    List {
        ChangelogEntryRow(
            entry: ChangelogEntry(
                from: NodeEvent(
                    timestamp: Date(),
                    type: .insertNode,
                    payload: try! JSONEncoder().encode(InsertNodePayload(
                        nodeId: "a3f2",
                        title: "Buy groceries",
                        parentId: nil,
                        position: 0
                    )),
                    batchId: "batch1"
                ),
                nodeTree: NodeTree()
            )
        )

        ChangelogEntryRow(
            entry: ChangelogEntry(
                from: NodeEvent(
                    timestamp: Date().addingTimeInterval(-3600),
                    type: .renameNode,
                    payload: try! JSONEncoder().encode(RenameNodePayload(
                        nodeId: "b7e1",
                        oldTitle: "Buy groceries",
                        newTitle: "Buy organic groceries"
                    )),
                    batchId: "batch2"
                ),
                nodeTree: NodeTree()
            )
        )

        ChangelogEntryRow(
            entry: ChangelogEntry(
                from: NodeEvent(
                    timestamp: Date().addingTimeInterval(-7200),
                    type: .deleteNode,
                    payload: try! JSONEncoder().encode(DeleteNodePayload(
                        nodeId: "c4d3"
                    )),
                    batchId: "batch3"
                ),
                nodeTree: {
                    let tree = NodeTree()
                    // Simulate a deleted node still in tree
                    tree.rebuildFromEvents([
                        NodeEvent(
                            timestamp: Date().addingTimeInterval(-10000),
                            type: .insertNode,
                            payload: try! JSONEncoder().encode(InsertNodePayload(
                                nodeId: "c4d3",
                                title: "Old completed task",
                                parentId: nil,
                                position: 0
                            )),
                            batchId: "old"
                        )
                    ])
                    return tree
                }()
            )
        )
    }
    .listStyle(.plain)
    .environmentObject(FontPreference())
}
