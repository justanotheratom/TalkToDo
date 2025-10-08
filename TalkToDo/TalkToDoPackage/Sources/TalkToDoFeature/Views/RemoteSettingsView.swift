import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct RemoteSettingsView: View {
    @Bindable private var settingsStore: VoiceProcessingSettingsStore

    @State private var pasteFeedback: (message: String, isError: Bool)?

    public init(settingsStore: VoiceProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
    }

    private var envAPIKey: String? {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEnvKey: Bool {
        if let key = envAPIKey, !key.isEmpty {
            return true
        }
        return false
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "cloud")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini 2.5 Flash Lite")
                            .font(.headline)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if hasEnvKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using GEMINI_API_KEY from environment")
                            .font(.caption)
                    }
                } else {
                    switch settingsStore.geminiKeyStatus {
                    case .missing:
                        Button(action: pasteGeminiKey) {
                            Label("Paste API Key", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderedProminent)

                    case .present(let masked):
                        LabeledContent("API Key", value: masked)
                            .foregroundStyle(.secondary)

                        Button(role: .destructive, action: clearGeminiKey) {
                            Label("Remove API Key", systemImage: "trash")
                        }
                    }

                    if let feedback = pasteFeedback {
                        Text(feedback.message)
                            .font(.caption)
                            .foregroundStyle(feedback.isError ? Color.red : Color.green)
                    }
                }
            } header: {
                Text("Configuration")
            } footer: {
                if hasEnvKey {
                    Text("Your API key is automatically loaded from the environment. No need to paste it manually.")
                } else {
                    Text("Get a free API key from Google AI Studio. Your audio will be uploaded to Google for processing.")
                }
            }

            Section {
                Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                    Label("Get a Free API Key", systemImage: "arrow.up.forward.app")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.orange)
                        Text("Privacy Notice")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("Remote mode uploads your voice recordings to Google's servers. Audio is processed and deleted immediately. Review Google's privacy policy for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Remote Processing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var statusText: String {
        if hasEnvKey {
            return "Using environment variable"
        }
        switch settingsStore.geminiKeyStatus {
        case .missing:
            return "Setup required"
        case .present:
            return "Ready to use"
        }
    }

    private func pasteGeminiKey() {
        #if os(iOS)
        let clipboard = UIPasteboard.general.string
        #else
        let clipboard = NSPasteboard.general.string(forType: .string)
        #endif

        guard let value = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            setPasteFeedback("Clipboard is empty", isError: true)
            return
        }

        settingsStore.updateGeminiAPIKey(value)
        setPasteFeedback("API key saved", isError: false)
    }

    private func clearGeminiKey() {
        settingsStore.updateGeminiAPIKey(nil)
        setPasteFeedback("API key removed", isError: false)
    }

    private func setPasteFeedback(_ message: String, isError: Bool) {
        pasteFeedback = (message, isError)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if pasteFeedback?.message == message {
                pasteFeedback = nil
            }
        }
    }
}
