import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct CheckboxView: View {
    let isChecked: Bool
    let action: () -> Void

    public init(isChecked: Bool, action: @escaping () -> Void) {
        self.isChecked = isChecked
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isChecked ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(isChecked ? Color.accentColor : Color.clear))
                    .frame(width: 24, height: 24)
                    .shadow(color: isChecked ? Color.accentColor.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)

                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isChecked ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isChecked)
    }
}

#Preview {
    VStack(spacing: 20) {
        CheckboxView(isChecked: false, action: {})
        CheckboxView(isChecked: true, action: {})
    }
    .padding()
}
