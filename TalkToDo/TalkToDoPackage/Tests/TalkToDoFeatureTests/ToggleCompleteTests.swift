import XCTest
import SwiftData
@testable import TalkToDoFeature
@testable import TalkToDoShared

@available(iOS 18.0, macOS 15.0, *)
final class ToggleCompleteTests: XCTestCase {
    var modelContext: ModelContext!
    var eventStore: EventStore!
    var nodeTree: NodeTree!

    @MainActor
    override func setUp() async throws {
        let container = try ModelContainer(
            for: NodeEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = container.mainContext
        nodeTree = NodeTree()
        eventStore = EventStore(modelContext: modelContext, nodeTree: nodeTree)
    }

    @MainActor
    func test_toggleComplete_createsEvent() throws {
        // Given - insert a node first
        let insertPayload = InsertNodePayload(
            nodeId: "test1",
            title: "Test Task",
            parentId: nil,
            position: 0
        )
        let insertData = try JSONEncoder().encode(insertPayload)
        let insertEvent = NodeEvent(
            type: .insertNode,
            payload: insertData,
            batchId: "batch1"
        )
        try eventStore.appendEvent(insertEvent)

        // When - toggle completion
        let togglePayload = ToggleCompletePayload(
            nodeId: "test1",
            isCompleted: true
        )
        let toggleData = try JSONEncoder().encode(togglePayload)
        let toggleEvent = NodeEvent(
            type: .toggleComplete,
            payload: toggleData,
            batchId: "batch2"
        )
        try eventStore.appendEvent(toggleEvent)

        // Then
        let events = try eventStore.fetchAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.eventType, .toggleComplete)
    }

    @MainActor
    func test_toggleComplete_updatesNodeTree() throws {
        // Given - insert a node
        let insertPayload = InsertNodePayload(
            nodeId: "test1",
            title: "Test Task",
            parentId: nil,
            position: 0
        )
        let insertData = try JSONEncoder().encode(insertPayload)
        let insertEvent = NodeEvent(
            type: .insertNode,
            payload: insertData,
            batchId: "batch1"
        )
        try eventStore.appendEvent(insertEvent)

        // When - toggle completion
        let togglePayload = ToggleCompletePayload(
            nodeId: "test1",
            isCompleted: true
        )
        let toggleData = try JSONEncoder().encode(togglePayload)
        let toggleEvent = NodeEvent(
            type: .toggleComplete,
            payload: toggleData,
            batchId: "batch2"
        )
        try eventStore.appendEvent(toggleEvent)

        // Then - node should be completed
        let node = nodeTree.findNode(id: "test1")
        XCTAssertEqual(node?.isCompleted, true)
    }

    @MainActor
    func test_toggleComplete_canBeUndone() throws {
        // Given - insert and complete a node
        let insertPayload = InsertNodePayload(
            nodeId: "test1",
            title: "Test Task",
            parentId: nil,
            position: 0
        )
        let insertData = try JSONEncoder().encode(insertPayload)
        let insertEvent = NodeEvent(
            type: .insertNode,
            payload: insertData,
            batchId: "batch1"
        )
        try eventStore.appendEvent(insertEvent)

        let togglePayload = ToggleCompletePayload(
            nodeId: "test1",
            isCompleted: true
        )
        let toggleData = try JSONEncoder().encode(togglePayload)
        let toggleEvent = NodeEvent(
            type: .toggleComplete,
            payload: toggleData,
            batchId: "batch2"
        )
        try eventStore.appendEvent(toggleEvent)

        // Verify node is completed
        XCTAssertEqual(nodeTree.findNode(id: "test1")?.isCompleted, true)

        // When - undo the completion
        try eventStore.undoBatch("batch2")

        // Then - node should not be completed
        let node = nodeTree.findNode(id: "test1")
        XCTAssertEqual(node?.isCompleted, false)
    }

    @MainActor
    func test_toggleComplete_multipleTimes() throws {
        // Given - insert a node
        let insertPayload = InsertNodePayload(
            nodeId: "test1",
            title: "Test Task",
            parentId: nil,
            position: 0
        )
        let insertData = try JSONEncoder().encode(insertPayload)
        let insertEvent = NodeEvent(
            type: .insertNode,
            payload: insertData,
            batchId: "batch1"
        )
        try eventStore.appendEvent(insertEvent)

        // When - toggle multiple times
        for i in 0..<5 {
            let isCompleted = i % 2 == 0  // Alternate between true/false
            let togglePayload = ToggleCompletePayload(
                nodeId: "test1",
                isCompleted: isCompleted
            )
            let toggleData = try JSONEncoder().encode(togglePayload)
            let toggleEvent = NodeEvent(
                type: .toggleComplete,
                payload: toggleData,
                batchId: "batch\(i + 2)"
            )
            try eventStore.appendEvent(toggleEvent)
        }

        // Then - final state should be not completed (last toggle was false)
        let node = nodeTree.findNode(id: "test1")
        XCTAssertEqual(node?.isCompleted, false)
    }
}
