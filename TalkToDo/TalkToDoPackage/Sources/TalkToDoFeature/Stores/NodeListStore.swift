import Foundation
import Observation

@available(iOS 18.0, macOS 15.0, *)
@MainActor
@Observable
public final class NodeListStore {
    public var showCompleted = false
    public var highlightedNodes: [String: HighlightType] = [:]
    public var recordingNodeId: String?
    public var selectedNodeId: String?  // Node selected for voice context
    public var completedNodesToRemove: Set<String> = []

    public init() {}

    public func highlightNodes(_ nodeIds: [String], type: HighlightType) {
        for nodeId in nodeIds {
            highlightedNodes[nodeId] = type
        }

        // Auto-clear highlights after duration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(type.duration + 0.5))
            for nodeId in nodeIds {
                highlightedNodes.removeValue(forKey: nodeId)
            }
        }
    }

    public func setRecordingNode(_ nodeId: String?) {
        recordingNodeId = nodeId
    }

    public func setSelectedNode(_ nodeId: String?) {
        selectedNodeId = nodeId
    }

    public func scheduleRemoval(of nodeId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            completedNodesToRemove.insert(nodeId)
        }
    }

    public func restoreNode(_ nodeId: String) {
        completedNodesToRemove.remove(nodeId)
    }

    public func clearCompletedRemovals() {
        completedNodesToRemove.removeAll()
    }
}
