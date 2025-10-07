import Foundation

/// Represents the type of visual highlight to show on a node
public enum HighlightType: Equatable {
    case added      // Green flash - node was just created
    case edited     // Yellow flash - node title was changed
    case deleted    // Red flash - node is being removed
    case undone     // Blue flash - operation was undone

    /// Duration in seconds to show the highlight
    public var duration: Double {
        switch self {
        case .added: return 1.0
        case .edited: return 0.8
        case .deleted: return 0.8
        case .undone: return 1.0
        }
    }

    /// Background color for the highlight
    public var color: String {
        switch self {
        case .added: return "green"
        case .edited: return "yellow"
        case .deleted: return "red"
        case .undone: return "blue"
        }
    }
}
