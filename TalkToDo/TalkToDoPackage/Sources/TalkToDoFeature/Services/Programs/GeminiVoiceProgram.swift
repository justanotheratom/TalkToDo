import Foundation
import TalkToDoShared

public struct GeminiVoiceProgram: AIProgram {
    public let id: String
    public let displayName: String
    public let modelConfig: ModelConfig
    public let systemPrompt: String
    public let inputType: AIProgramInputType
    public let outputType: AIProgramOutputType
    
    public init() {
        self.id = "gemini-voice-v1"
        self.displayName = "Gemini Voice (v1)"
        self.modelConfig = ModelConfigCatalog.shared.config(for: "gemini-flash-lite")!
        self.systemPrompt = ProgramPrompts.voiceToStructureV1
        self.inputType = .audio
        self.outputType = .json
    }
}

public struct GeminiVoiceProgramV2: AIProgram {
    public let id: String
    public let displayName: String
    public let modelConfig: ModelConfig
    public let systemPrompt: String
    public let inputType: AIProgramInputType
    public let outputType: AIProgramOutputType
    
    public init() {
        self.id = "gemini-voice-v2"
        self.displayName = "Gemini Voice (v2)"
        self.modelConfig = ModelConfigCatalog.shared.config(for: "gemini-flash-lite")!
        self.systemPrompt = ProgramPrompts.voiceToStructureV2
        self.inputType = .audio
        self.outputType = .json
    }
}
