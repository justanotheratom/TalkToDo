import Foundation
import TalkToDoShared

extension ProcessingSettingsStore {
    public func resolvedVoiceProgram() -> any AIProgram {
        if let id = selectedVoiceProgramId,
           let program = ProgramCatalog.shared.program(for: id) {
            return program
        }
        return ProgramCatalog.shared.defaultVoiceProgram()
    }
    
    public func resolvedTextProgram() -> any AIProgram {
        if let id = selectedTextProgramId,
           let program = ProgramCatalog.shared.program(for: id) {
            return program
        }
        return ProgramCatalog.shared.defaultTextProgram()
    }
}
