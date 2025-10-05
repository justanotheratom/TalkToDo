import SwiftUI

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
            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 60, height: 60)

                    Image(systemName: micIconName)
                        .font(.system(size: 24))
                        .foregroundStyle(micIconColor)
                }
            }
            .buttonStyle(MicButtonStyle(
                isEnabled: isEnabled,
                onPressDown: onPressDown,
                onPressUp: onPressUp
            ))
            .disabled(!isEnabled)
            .animation(.easeInOut(duration: 0.2), value: status)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Styling

    private var micButtonColor: Color {
        switch status {
        case .idle:
            return .blue
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

/// Custom button style for press-and-hold behavior
@available(iOS 18.0, macOS 15.0, *)
struct MicButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let onPressDown: () -> Void
    let onPressUp: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if isEnabled {
                    if newValue {
                        onPressDown()
                    } else if oldValue {
                        onPressUp()
                    }
                }
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
