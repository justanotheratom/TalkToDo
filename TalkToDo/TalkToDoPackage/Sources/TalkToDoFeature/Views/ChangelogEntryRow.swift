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
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: entry.icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Description
                Text(entry.description)
                    .font(fontPreference.selectedFont.body)
                    .foregroundStyle(.primary)

                // Details (if any)
                if let details = entry.details {
                    Text(details)
                        .font(fontPreference.selectedFont.caption)
                        .foregroundStyle(.secondary)
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

            Spacer()
        }
        .padding(.vertical, 8)
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
                nodeTree: NodeTree()
            )
        )
    }
    .listStyle(.plain)
    .environmentObject(FontPreference())
}
