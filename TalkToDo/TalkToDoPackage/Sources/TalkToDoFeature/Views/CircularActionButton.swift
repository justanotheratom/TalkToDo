import SwiftUI

/// Reusable circular action button with gradient background and shadow.
/// Used for send buttons in the voice input interface.
@available(iOS 18.0, macOS 15.0, *)
struct CircularActionButton: View {
    enum ButtonStyle {
        case primary
        case secondary

        var color: Color {
            switch self {
            case .primary: return Color(red: 1.0, green: 0.478, blue: 0.361) // Coral accent
            case .secondary: return .gray
            }
        }
    }

    let icon: String
    let style: ButtonStyle
    let size: CGFloat
    let action: () -> Void
    let accessibilityLabel: String?

    init(
        icon: String,
        style: ButtonStyle = .primary,
        size: CGFloat = 40,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(style.color.gradient)
                    .frame(width: size, height: size)
                    .shadow(color: style.color.opacity(0.3), radius: 6, y: 3)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    private var iconSize: CGFloat {
        size * 0.45
    }
}
