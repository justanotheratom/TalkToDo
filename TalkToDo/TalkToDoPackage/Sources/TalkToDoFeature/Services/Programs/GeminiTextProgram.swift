import Foundation
import TalkToDoShared

public struct GeminiTextProgram: AIProgram {
    public let id: String
    public let displayName: String
    public let modelConfig: ModelConfig
    public let systemPrompt: String
    public let inputType: AIProgramInputType
    public let outputType: AIProgramOutputType
    
    public init() {
        self.id = "gemini-text-v1"
        self.displayName = "Gemini Text (v1)"
        self.modelConfig = ModelConfigCatalog.shared.config(for: "gemini-flash-lite")!
        self.systemPrompt = ProgramPrompts.textToStructureV1
        self.inputType = .text
        self.outputType = .json
    }
}
