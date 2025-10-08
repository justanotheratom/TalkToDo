import Foundation
import TalkToDoShared

public final class ProgramCatalog: @unchecked Sendable {
    public static let shared = ProgramCatalog()
    
    public let allPrograms: [any AIProgram]
    
    private init() {
        self.allPrograms = [
            GeminiVoiceProgram(),
            GeminiVoiceProgramV2(),
            GeminiTextProgram()
        ]
    }
    
    public var voicePrograms: [any AIProgram] {
        allPrograms.filter { $0.inputType == .audio }
    }
    
    public var textPrograms: [any AIProgram] {
        allPrograms.filter { $0.inputType == .text }
    }
    
    public func program(for id: String) -> (any AIProgram)? {
        allPrograms.first { $0.id == id }
    }
    
    public func defaultVoiceProgram() -> any AIProgram {
        voicePrograms.first ?? GeminiVoiceProgram()
    }
    
    public func defaultTextProgram() -> any AIProgram {
        textPrograms.first ?? GeminiTextProgram()
    }
}
