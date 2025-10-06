import SwiftUI

/// Reusable status banner component for displaying informational or warning messages.
/// Used for microphone errors, permission states, and other temporary notifications.
@available(iOS 18.0, macOS 15.0, *)
struct StatusBanner: View {
    let text: String
    let color: Color
    let icon: String

    init(text: String, color: Color = .secondary, icon: String = "exclamationmark.circle.fill") {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                }
        }
        .shadow(color: color.opacity(0.15), radius: 6, y: 3)
    }
}
