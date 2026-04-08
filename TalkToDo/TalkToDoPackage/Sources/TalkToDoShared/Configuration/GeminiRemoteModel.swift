import Foundation

public enum GeminiRemoteModel: String, CaseIterable, Sendable {
    case flashPreview = "gemini-3-flash-preview"
    case proPreview = "gemini-3.1-pro-preview"
    case flashLitePreview = "gemini-3.1-flash-lite-preview"

    public static let `default`: GeminiRemoteModel = .flashLitePreview

    public var displayName: String {
        switch self {
        case .flashPreview:
            return "Gemini 3 Flash Preview"
        case .proPreview:
            return "Gemini 3.1 Pro Preview"
        case .flashLitePreview:
            return "Gemini 3.1 Flash Lite Preview"
        }
    }

    public var summary: String {
        switch self {
        case .flashPreview:
            return "Fast frontier model with grounding and search support."
        case .proPreview:
            return "Highest-depth reasoning model for complex multimodal tasks."
        case .flashLitePreview:
            return "Lowest-cost model for high-volume structured task processing."
        }
    }
}
