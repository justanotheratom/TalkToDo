import SwiftUI
import TalkToDoShared

/// Mini card representation of a todo node for changelog display
@available(iOS 18.0, macOS 15.0, *)
public struct ChangelogNodeCard: View {
    @EnvironmentObject private var fontPreference: FontPreference

    let title: String
    let isDeleted: Bool
    let isCompleted: Bool
    let parentTitle: String?

    public init(title: String, isDeleted: Bool = false, isCompleted: Bool = false, parentTitle: String? = nil) {
        self.title = title
        self.isDeleted = isDeleted
        self.isCompleted = isCompleted
        self.parentTitle = parentTitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Parent context
            if let parent = parentTitle {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(parent)
                        .font(fontPreference.selectedFont.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }

            // Card
            cardContent
        }
    }

    private var cardContent: some View {
        HStack(spacing: 8) {
            // Checkbox indicator
            if isCompleted {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            } else if !isDeleted {
                Image(systemName: "square")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            // Title
            Text(title)
                .font(fontPreference.selectedFont.subheadline)
                .foregroundStyle(isDeleted ? .secondary : .primary)
                .strikethrough(isDeleted || isCompleted)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .opacity(isDeleted ? 0.6 : 1.0)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(white: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isDeleted
                    ? Color.red.opacity(0.3)
                    : Color.secondary.opacity(0.2),
                lineWidth: 1
            )
    }
}

#Preview {
    VStack(spacing: 12) {
        ChangelogNodeCard(title: "Buy groceries")

        ChangelogNodeCard(title: "Call accountant", parentTitle: "File my tax returns")

        ChangelogNodeCard(title: "Buy groceries", isCompleted: true)

        ChangelogNodeCard(title: "Old task that was deleted", isDeleted: true, parentTitle: "Old Project")
    }
    .padding()
    .background(Color(white: 0.95))
    .environmentObject(FontPreference())
}
