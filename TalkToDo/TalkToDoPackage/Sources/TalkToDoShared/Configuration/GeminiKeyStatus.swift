public enum GeminiKeyStatus: Sendable, Equatable {
    case missing
    case present(masked: String)
}
