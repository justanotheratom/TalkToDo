import SwiftUI

#if os(iOS)
import UIKit
#endif

@available(iOS 18.0, macOS 15.0, *)
public struct MicrophoneInputBar: View {
    let status: VoiceInputStore.Status
    let isEnabled: Bool
    let onPressDown: () -> Void
    let onPressUp: () -> Void

    public init(
        status: VoiceInputStore.Status,
        isEnabled: Bool,
        onPressDown: @escaping () -> Void,
        onPressUp: @escaping () -> Void
    ) {
        self.status = status
        self.isEnabled = isEnabled
        self.onPressDown = onPressDown
        self.onPressUp = onPressUp
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Feedback message
            if case .error(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if case .disabled(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Microphone button
            microphoneButton
        }
        .padding(.vertical, 12)
    }

    private var microphoneButton: some View {
        let longPressGesture = LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                guard isEnabled, status.allowsInteraction else { return }
#if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
                onPressDown()
            }

        let dragGesture = DragGesture(minimumDistance: 0)
            .onEnded { _ in
                if status == .recording {
#if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                    onPressUp()
                }
            }

        return ZStack {
            Circle()
                .fill(micButtonColor)
                .frame(width: 60, height: 60)

            Image(systemName: micIconName)
                .font(.system(size: 24))
                .foregroundStyle(micIconColor)
        }
        .scaleEffect(status == .recording ? 1.05 : 1.0)
        .opacity(isEnabled ? 1.0 : 0.5)
        .contentShape(Circle())
        .simultaneousGesture(longPressGesture.sequenced(before: dragGesture))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: status)
    }

    // MARK: - Styling

    private var micButtonColor: Color {
        switch status {
        case .idle:
            return .accentColor
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .disabled:
            return .gray.opacity(0.3)
        case .error:
            return .orange.opacity(0.5)
        }
    }

    private var micIconName: String {
        switch status {
        case .idle, .disabled, .error:
            return "mic.fill"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        }
    }

    private var micIconColor: Color {
        switch status {
        case .idle, .recording, .transcribing:
            return .white
        case .disabled, .error:
            return .gray
        }
    }
}

#Preview("Idle") {
    MicrophoneInputBar(
        status: .idle,
        isEnabled: true,
        onPressDown: { print("Press down") },
        onPressUp: { print("Press up") }
    )
}

#Preview("Recording") {
    MicrophoneInputBar(
        status: .recording,
        isEnabled: true,
        onPressDown: {},
        onPressUp: {}
    )
}

#Preview("Error") {
    MicrophoneInputBar(
        status: .error(message: "Couldn't access the microphone"),
        isEnabled: false,
        onPressDown: {},
        onPressUp: {}
    )
}
