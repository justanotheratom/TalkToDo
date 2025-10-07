import SwiftUI
import TalkToDoShared

#if os(iOS)
import UIKit
#endif

@available(iOS 18.0, macOS 15.0, *)
public struct MicrophoneInputBar: View {
    @EnvironmentObject private var fontPreference: FontPreference

    let status: VoiceInputStore.Status
    let isEnabled: Bool
    let liveTranscript: String?
    let onPressDown: () -> Void
    let onPressUp: () -> Void
    let onSendText: (String) -> Void

    @State private var isTextInputMode = false
    @State private var textInputContent = ""
    @FocusState private var isTextFieldFocused: Bool

    public init(
        status: VoiceInputStore.Status,
        isEnabled: Bool,
        liveTranscript: String?,
        onPressDown: @escaping () -> Void,
        onPressUp: @escaping () -> Void,
        onSendText: @escaping (String) -> Void
    ) {
        self.status = status
        self.isEnabled = isEnabled
        self.liveTranscript = liveTranscript
        self.onPressDown = onPressDown
        self.onPressUp = onPressUp
        self.onSendText = onSendText
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let transcript = liveTranscript,
               !transcript.isEmpty,
               status == .recording {
                liveTranscriptOverlay(transcript: transcript)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                if isTextInputMode {
                    textInputField
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background {
                            inputBarBackground
                                .ignoresSafeArea(edges: .bottom)
                        }
                } else {
                    inputButton
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .overlay(alignment: .top) {
                if let feedback = microphoneFeedback {
                    statusBanner(text: feedback.text, color: feedback.color)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Input Button (Voice)

    @ViewBuilder
    private var inputButton: some View {
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

        let tapGesture = TapGesture()
            .onEnded {
                guard status != .recording, status != .transcribing else { return }
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isTextInputMode = true
                    isTextFieldFocused = true
                }
            }

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(microphoneBackgroundColor.gradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: microphoneBackgroundColor.opacity(0.3), radius: 6, y: 3)

                microphoneIcon
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: status == .recording)
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(microphonePrimaryText)
                    .font(fontPreference.selectedFont.subheadline)
                    .foregroundStyle(microphonePrimaryColor)

                if let detail = microphoneDetailText {
                    Text(detail)
                        .font(fontPreference.selectedFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            if microphoneShowsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(microphoneBackgroundColor)
            } else {
                ZStack {
                    Circle()
                        .fill(microphoneBackgroundColor.gradient)
                        .frame(width: 40, height: 40)
                        .shadow(color: microphoneBackgroundColor.opacity(0.3), radius: 6, y: 3)
                    
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .shadow(color: Color.accentColor.opacity(0.15), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.3),
                            Color.accentColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .scaleEffect(status == .recording ? 1.02 : 1.0)
        .opacity(isEnabled ? 1.0 : 0.5)
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(longPressGesture.sequenced(before: dragGesture))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(microphoneAccessibilityLabel)
        .accessibilityHint(microphoneAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Text Input Field

    @ViewBuilder
    private var textInputField: some View {
        HStack(spacing: 10) {
            TextField("Type your message...", text: $textInputContent)
                .focused($isTextFieldFocused)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
                .onSubmit {
                    sendTextInput()
                }

            CircularActionButton(
                icon: "arrow.up",
                style: .primary,
                size: 40,
                action: sendTextInput
            )
            .disabled(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(textInputContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isTextInputMode = false
                    textInputContent = ""
                    isTextFieldFocused = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func sendTextInput() {
        let trimmed = textInputContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif

        onSendText(trimmed)
        textInputContent = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isTextInputMode = false
            isTextFieldFocused = false
        }
    }

    // MARK: - Supporting Views

    private func statusBanner(text: String, color: Color) -> some View {
        StatusBanner(text: text, color: color)
            .offset(y: -10)
    }

    @ViewBuilder
    private var inputBarBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.99),
                    Color(red: 0.96, green: 0.97, blue: 0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: -2)
    }

    // MARK: - Microphone Styling

    private var microphoneIcon: Image {
        switch status {
        case .idle:
            return Image(systemName: "mic.fill")
        case .requestingPermission:
            return Image(systemName: "exclamationmark.circle.fill")
        case .recording:
            return Image(systemName: "waveform")
        case .transcribing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .disabled:
            return Image(systemName: "mic.slash.fill")
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var microphoneBackgroundColor: Color {
        switch status {
        case .idle:
            return Color(red: 1.0, green: 0.478, blue: 0.361) // Coral accent
        case .requestingPermission:
            return Color(red: 1.0, green: 0.6, blue: 0.4) // Lighter coral
        case .recording:
            return Color.red
        case .transcribing:
            return Color.purple
        case .disabled:
            return Color.gray
        case .error:
            return Color.orange
        }
    }

    private var microphonePrimaryColor: Color {
        switch status {
        case .idle, .requestingPermission, .transcribing:
            return .primary
        case .recording:
            return .red
        case .disabled:
            return .secondary
        case .error:
            return .orange
        }
    }

    private var microphonePrimaryText: String {
        switch status {
        case .idle:
            return "Hold to talk, Tap to type"
        case .requestingPermission:
            return "Requesting access…"
        case .recording:
            return "Recording…"
        case .transcribing:
            return "Processing speech…"
        case .disabled:
            return "Microphone unavailable"
        case .error:
            return "Error occurred"
        }
    }

    private var microphoneDetailText: String? {
        switch status {
        case .idle:
            return nil
        case .requestingPermission:
            return "Grant permissions to continue"
        case .recording:
            return "Release to send"
        case .transcribing:
            return nil
        case .disabled(let message):
            return message.isEmpty ? nil : message
        case .error(let message):
            return message.isEmpty ? nil : message
        }
    }

    private var microphoneShowsProgress: Bool {
        switch status {
        case .requestingPermission, .transcribing:
            return true
        default:
            return false
        }
    }

    private var microphoneAccessibilityLabel: String {
        switch status {
        case .idle:
            return "Microphone button. Tap and hold to record your message or tap to type."
        case .requestingPermission:
            return "Requesting microphone permission."
        case .recording:
            return "Recording in progress. Release to send."
        case .transcribing:
            return "Transcribing your speech."
        case .disabled:
            return "Microphone unavailable."
        case .error:
            return "Microphone error. Tap and hold to retry."
        }
    }

    private var microphoneAccessibilityHint: String {
        switch status {
        case .idle:
            return "Double tap and hold to record, release to send. Or tap once to type."
        case .recording:
            return "Release to send your voice message."
        case .requestingPermission:
            return "Grant microphone permissions in Settings."
        case .transcribing:
            return "Please wait while processing completes."
        case .disabled:
            return "Enable microphone in Settings to use voice input."
        case .error:
            return "Tap and hold again to retry."
        }
    }

    private var microphoneFeedback: (text: String, color: Color)? {
        switch status {
        case .disabled(let message):
            return (message, .secondary)
        case .error(let message):
            return (message, .orange)
        default:
            return nil
        }
    }

    private func liveTranscriptOverlay(transcript: String) -> some View {
        Text(transcript)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.thinMaterial)
            }
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            .padding([.leading, .top], 6)
    }
}

#Preview("Idle") {
    MicrophoneInputBar(
        status: .idle,
        isEnabled: true,
        liveTranscript: nil,
        onPressDown: { print("Press down") },
        onPressUp: { print("Press up") },
        onSendText: { print("Send text: \($0)") }
    )
}

#Preview("Recording") {
    MicrophoneInputBar(
        status: .recording,
        isEnabled: true,
        liveTranscript: "Drafting your to-do...",
        onPressDown: {},
        onPressUp: {},
        onSendText: { _ in }
    )
}

#Preview("Error") {
    MicrophoneInputBar(
        status: .error(message: "Couldn't access the microphone"),
        isEnabled: false,
        liveTranscript: nil,
        onPressDown: {},
        onPressUp: {},
        onSendText: { _ in }
    )
}
