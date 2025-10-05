import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct UndoPill: View {
    let isVisible: Bool
    let onTap: () -> Void

    public init(isVisible: Bool, onTap: @escaping () -> Void) {
        self.isVisible = isVisible
        self.onTap = onTap
    }

    public var body: some View {
        if isVisible {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)

                    Text("Undo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.8))
                )
                .foregroundStyle(.white)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        UndoPill(isVisible: true, onTap: { print("Undo tapped") })
    }
    .padding()
}
