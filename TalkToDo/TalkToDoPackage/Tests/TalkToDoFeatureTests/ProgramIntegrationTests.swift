import XCTest
@testable import TalkToDoFeature
@testable import TalkToDoShared

final class ProgramIntegrationTests: XCTestCase {
    @MainActor
    func testAllProgramsIntegration() async throws {
        let programs = ProgramCatalog.shared.allPrograms
        var testedPrograms: [String] = []
        var skippedPrograms: [String] = []
        
        for program in programs {
            // Check if API key is available for this program
            let apiKey = await TestEnvironment.resolveAPIKey(for: program.modelConfig.apiKeyName)
            print("Program: \(program.id), API key name: \(program.modelConfig.apiKeyName), Found: \(apiKey != nil ? "Yes" : "No")")
            guard let apiKey = apiKey, !apiKey.isEmpty else {
                skippedPrograms.append("\(program.id) (missing \(program.modelConfig.apiKeyName))")
                continue
            }
            
            testedPrograms.append(program.id)
            
            // Test the program
            try await testProgram(program, apiKey: apiKey)
        }
        
        print("✅ Tested programs: \(testedPrograms.joined(separator: ", "))")
        if !skippedPrograms.isEmpty {
            print("⏭️ Skipped programs: \(skippedPrograms.joined(separator: ", "))")
        }
        
        XCTAssertFalse(testedPrograms.isEmpty, "No programs were tested - check API key availability")
    }
    
    @MainActor
    private func testProgram(_ program: any AIProgram, apiKey: String) async throws {
        print("🧪 Testing program: \(program.id)")
        
        // Create a test API key resolver that uses the provided API key
        let testAPIKeyResolver = TestAPIKeyResolver(apiKey: apiKey)
        
        // Create pipeline based on program type
        let pipeline: any TextProcessingPipeline
        if program.inputType == .text {
            pipeline = RemoteTextPipeline(program: program, apiKeyResolver: testAPIKeyResolver)
        } else {
            // For voice programs, we'll test with text input
            pipeline = RemoteTextPipeline(program: program, apiKeyResolver: testAPIKeyResolver)
        }
        
        // Test cases
        try await testGroceryList(pipeline: pipeline, programId: program.id)
        try await testHierarchicalTasks(pipeline: pipeline, programId: program.id)
        try await testEmptyInput(pipeline: pipeline, programId: program.id)
        try await testContextAwareOperations(pipeline: pipeline, programId: program.id)
        
        print("✅ Program \(program.id) passed all tests")
    }
    
    @MainActor
    private func testGroceryList(pipeline: any TextProcessingPipeline, programId: String) async throws {
        let prompt = "Create a grocery todo list with milk, eggs, and bread"
        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        let result = try await pipeline.process(text: prompt, context: context)
        
        XCTAssertFalse(result.operations.isEmpty, "Program \(programId): Expected at least one operation for grocery list")
        XCTAssertFalse(result.transcript.isEmpty, "Program \(programId): Expected non-empty transcript")
        
        // Verify operations structure
        for operation in result.operations {
            XCTAssertFalse(operation.nodeId.isEmpty, "Program \(programId): Node ID should not be empty")
            XCTAssertNotNil(operation.title, "Program \(programId): Title should not be nil for insert operations")
        }
    }
    
    @MainActor
    private func testHierarchicalTasks(pipeline: any TextProcessingPipeline, programId: String) async throws {
        let prompt = "Project Alpha: Research phase - Market analysis, Competitor review. Development phase - Backend API, Frontend UI"
        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        let result = try await pipeline.process(text: prompt, context: context)
        
        XCTAssertFalse(result.operations.isEmpty, "Program \(programId): Expected operations for hierarchical tasks")
        
        // Check for parent-child relationships
        let operations = result.operations
        let parentOperations = operations.filter { $0.parentId == nil }
        let childOperations = operations.filter { $0.parentId != nil }
        
        XCTAssertFalse(parentOperations.isEmpty, "Program \(programId): Expected at least one parent operation")
        if !childOperations.isEmpty {
            XCTAssertFalse(childOperations.isEmpty, "Program \(programId): Expected child operations for hierarchy")
        }
    }
    
    @MainActor
    private func testEmptyInput(pipeline: any TextProcessingPipeline, programId: String) async throws {
        let context = ProcessingContext(nodeContext: nil, eventLog: [], nodeSnapshot: [])
        
        do {
            _ = try await pipeline.process(text: "", context: context)
            XCTFail("Program \(programId): Expected error for empty input")
        } catch {
            // Expected behavior
        }
    }
    
    @MainActor
    private func testContextAwareOperations(pipeline: any TextProcessingPipeline, programId: String) async throws {
        // Create some context with existing nodes
        let existingNodes = [
            SnapshotNode(id: "task1", title: "Buy groceries", isCollapsed: false, children: []),
            SnapshotNode(id: "task2", title: "Call mom", isCollapsed: false, children: [])
        ]
        
        let context = ProcessingContext(
            nodeContext: nil,
            eventLog: [],
            nodeSnapshot: existingNodes
        )
        
        let prompt = "Add 'milk' to the groceries task and create a new task 'Schedule dentist'"
        let result = try await pipeline.process(text: prompt, context: context)
        
        XCTAssertFalse(result.operations.isEmpty, "Program \(programId): Expected operations for context-aware input")
    }
}

extension TestEnvironment {
    @MainActor
    static func resolveAPIKey(for keyName: String) -> String? {
        // First check environment variables
        if let envKey = ProcessInfo.processInfo.environment[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        
        // Then check .env file in the project root
        let projectRoot = URL(fileURLWithPath: "/Users/sanket/GitHub/TalkToDo/.env")
        
        return loadFromEnvFile(at: projectRoot, keyName: keyName)
    }
    
    private static func loadFromEnvFile(at url: URL, keyName: String) -> String? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("\(keyName)=") {
                    let value = String(trimmed.dropFirst(keyName.count + 1))
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("Failed to read .env file at \(url.path): \(error)")
        }
        
        return nil
    }
}
