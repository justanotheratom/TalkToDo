import Foundation
import Observation

/// Tracks recent node changes for visual highlighting
@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class ChangeTracker {
    public private(set) var highlightedNodes: [String: HighlightType] = [:]

    public init() {}

    /// Records that nodes were changed in a batch
    public func trackChanges(_ changes: [String: HighlightType]) {
        highlightedNodes = changes

        // Auto-clear after longest duration
        let maxDuration = changes.values.map(\.duration).max() ?? 1.0
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(maxDuration + 0.5))
            clearHighlights(Array(changes.keys))
        }
    }

    /// Records that operations were undone
    public func trackUndo(nodeIds: [String]) {
        var changes: [String: HighlightType] = [:]
        for nodeId in nodeIds {
            changes[nodeId] = .undone
        }
        trackChanges(changes)
    }

    /// Manually clear specific highlights
    public func clearHighlights(_ nodeIds: [String]) {
        for nodeId in nodeIds {
            highlightedNodes.removeValue(forKey: nodeId)
        }
    }

    /// Clear all highlights
    public func clearAll() {
        highlightedNodes.removeAll()
    }
}
