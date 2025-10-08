import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
public struct RemoteSettingsView: View {
    @Bindable private var settingsStore: ProcessingSettingsStore

    @State private var pasteFeedback: (message: String, isError: Bool)?
    @State private var selectedVoiceProgramId: String
    @State private var selectedTextProgramId: String

    public init(settingsStore: ProcessingSettingsStore) {
        self._settingsStore = Bindable(settingsStore)
        self._selectedVoiceProgramId = State(initialValue: settingsStore.selectedVoiceProgramId ?? ProgramCatalog.shared.defaultVoiceProgram().id)
        self._selectedTextProgramId = State(initialValue: settingsStore.selectedTextProgramId ?? ProgramCatalog.shared.defaultTextProgram().id)
    }

    private var voiceProgram: any AIProgram {
        ProgramCatalog.shared.program(for: selectedVoiceProgramId) ?? ProgramCatalog.shared.defaultVoiceProgram()
    }
    
    private var textProgram: any AIProgram {
        ProgramCatalog.shared.program(for: selectedTextProgramId) ?? ProgramCatalog.shared.defaultTextProgram()
    }
    
    private var allRequiredAPIKeys: Set<String> {
        var keys = Set<String>()
        keys.insert(voiceProgram.modelConfig.apiKeyName)
        keys.insert(textProgram.modelConfig.apiKeyName)
        return keys
    }

    public var body: some View {
        Form {
            Section("Voice Processing") {
                Picker("Voice Program", selection: $selectedVoiceProgramId) {
                    ForEach(ProgramCatalog.shared.voicePrograms, id: \.id) { program in
                        Text(program.displayName)
                            .tag(program.id)
                    }
                }
                .onChange(of: selectedVoiceProgramId) { _, newValue in
                    settingsStore.updateSelectedVoiceProgram(id: newValue)
                }
                
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voiceProgram.modelConfig.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Provider: \(voiceProgram.modelConfig.provider.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: convertToStatusBadge(settingsStore.apiKeyStatus(for: voiceProgram.modelConfig.apiKeyName)))
                }
            }
            
            Section("Text Processing") {
                Picker("Text Program", selection: $selectedTextProgramId) {
                    ForEach(ProgramCatalog.shared.textPrograms, id: \.id) { program in
                        Text(program.displayName)
                            .tag(program.id)
                    }
                }
                .onChange(of: selectedTextProgramId) { _, newValue in
                    settingsStore.updateSelectedTextProgram(id: newValue)
                }
                
                HStack {
                    Image(systemName: "text.cursor")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(textProgram.modelConfig.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Provider: \(textProgram.modelConfig.provider.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: convertToStatusBadge(settingsStore.apiKeyStatus(for: textProgram.modelConfig.apiKeyName)))
                }
            }

            Section {
                ForEach(Array(allRequiredAPIKeys).sorted(), id: \.self) { keyName in
                    APIKeyRow(
                        keyName: keyName,
                        status: settingsStore.apiKeyStatus(for: keyName),
                        onPaste: { pasteAPIKey(for: keyName) },
                        onClear: { clearAPIKey(for: keyName) },
                        feedback: pasteFeedback
                    )
                }
            } footer: {
                Text("API keys are stored securely in your device's keychain. Environment variables take precedence over stored keys.")
            }

            Section {
                ForEach(Array(allRequiredAPIKeys).sorted(), id: \.self) { keyName in
                    if let provider = getProviderForAPIKey(keyName) {
                        Link(destination: getAPIKeyURL(for: provider)) {
                            Label("Get \(keyName) API Key", systemImage: "arrow.up.forward.app")
                        }
                    }
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
                    Text("Remote mode uploads your voice recordings to the selected provider's servers. Audio is processed and deleted immediately. Review each provider's privacy policy for details.")
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

    private func getProviderForAPIKey(_ keyName: String) -> ModelProvider? {
        for config in ModelConfigCatalog.shared.allConfigs {
            if config.apiKeyName == keyName {
                return config.provider
            }
        }
        return nil
    }
    
    private func getAPIKeyURL(for provider: ModelProvider) -> URL {
        switch provider {
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")!
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic:
            return URL(string: "https://console.anthropic.com/")!
        }
    }

    private func pasteAPIKey(for keyName: String) {
        #if os(iOS)
        let clipboard = UIPasteboard.general.string
        #else
        let clipboard = NSPasteboard.general.string(forType: .string)
        #endif

        guard let value = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            setPasteFeedback("Clipboard is empty", isError: true)
            return
        }

        do {
            try settingsStore.storeAPIKey(for: keyName, value: value)
            setPasteFeedback("\(keyName) saved", isError: false)
        } catch {
            setPasteFeedback("Failed to save \(keyName)", isError: true)
        }
    }

    private func clearAPIKey(for keyName: String) {
        do {
            try settingsStore.deleteAPIKey(for: keyName)
            setPasteFeedback("\(keyName) removed", isError: false)
        } catch {
            setPasteFeedback("Failed to remove \(keyName)", isError: true)
        }
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

@available(iOS 18.0, macOS 15.0, *)
private struct APIKeyRow: View {
    let keyName: String
    let status: GeminiKeyStatus
    let onPaste: () -> Void
    let onClear: () -> Void
    let feedback: (message: String, isError: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(keyName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                StatusBadge(status: convertToStatusBadge(status))
            }
            
            switch status {
            case .missing:
                Button(action: onPaste) {
                    Label("Paste API Key", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                
            case .present:
                HStack {
                    Button(role: .destructive, action: onClear) {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: onPaste) {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if let feedback = feedback {
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(feedback.isError ? Color.red : Color.green)
            }
        }
        .padding(.vertical, 4)
    }
}

private func convertToStatusBadge(_ status: GeminiKeyStatus) -> StatusBadge.Status {
    switch status {
    case .missing:
        return .notConfigured
    case .present:
        return .ready
    }
}

