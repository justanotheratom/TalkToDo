import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct EmptyStateView: View {
    @State private var isPulsing = false

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            // Pulsing mic icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0.0 : 1.0)

                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }

            VStack(spacing: 8) {
                Text("Hold the mic and speak your thoughts")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Try: 'Weekend plans... hiking, groceries, call mom'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
}
