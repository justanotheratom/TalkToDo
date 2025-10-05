# TalkToDo Implementation Plan

## Executive Summary

TalkToDo is a voice-first hierarchical todo app that transforms natural speech into structured lists using on-device LLM inference. This plan leverages proven patterns from VoiceBot while introducing event-sourcing and CloudKit sync.

### Key Architectural Decisions

1. **16-bit Hex Node IDs (4 chars)**
   - Reduces LLM token overhead vs UUIDs
   - Example: "a3f2" instead of "550e8400-e29b-41d4-a716-446655440000"
   - 65,536 possible IDs (sufficient for todo lists)
   - Easier for LLM to generate and reference

2. **Event Sourcing with In-Memory Snapshot**
   - **On startup:** Fetch all events from SwiftData → rebuild snapshot via `rebuildFromEvents()`
   - **During runtime:** Every new event appended to log also updates snapshot via `applyEvent()`
   - Snapshot stays in sync with log at all times (no drift)
   - Fast UI rendering (read from snapshot), durable persistence (write to log)

3. **Batch-Based Undo**
   - Each user interaction gets a unique `batchId` (UUID)
   - All events from one voice input share the same batchId
   - Undo = delete all events with matching batchId, then rebuild snapshot
   - Much simpler than computing inverse operations!
   - Stack tracks last 20 batchIds for undo history

---

## Phase 1: Project Setup & Dependencies

### 1.1 Xcode Project Structure
- [ ] Create new Xcode project "TalkToDo" with iOS and macOS targets
  - iOS deployment target: 18.0
  - macOS deployment target: 15.7
  - Enable CloudKit capability for both targets
- [ ] Create Swift Package "TalkToDoPackage" in project root
  - Structure: `TalkToDoPackage/Sources/TalkToDoFeature/`
  - Add package dependency to both app targets
- [ ] Configure CloudKit container
  - Use default container (iCloud.com.yourteam.TalkToDo)
  - Enable Private Database sync
  - Configure CloudKit schema for event log

### 1.2 Dependencies & SDK Integration
- [ ] Add Leap SDK dependency to package
  - In Package.swift, add `.package(url: "https://github.com/liquidai/leap-ios-sdk", ...)`
  - Import LeapSDK, LeapSDKConstrainedGeneration, LeapModelDownloader
- [ ] Add required frameworks
  - Speech.framework (for SFSpeechRecognizer)
  - AVFoundation.framework (for audio)
  - SwiftData.framework (for event persistence)
  - CloudKit.framework (for sync)

### 1.3 Info.plist Configuration
- [ ] Add privacy usage descriptions
  - `NSSpeechRecognitionUsageDescription`: "TalkToDo uses speech recognition to convert your voice into structured tasks"
  - `NSMicrophoneUsageDescription`: "TalkToDo needs microphone access to capture your voice"

---

## Phase 2: Code Migration from VoiceBot

### 2.1 Speech Recognition (Copy & Adapt)
**Source:** `~/GitHub/VoiceBot/VoiceBotPackage/Sources/VoiceBotFeature/SpeechRecognitionService.swift`

- [ ] Copy `SpeechRecognitionService.swift` → `TalkToDoFeature/Services/`
  - ✅ Already actor-based with async/await
  - ✅ Handles on-device ASR with timeout fallback
  - ✅ Proper permission management
  - **No changes needed** - use as-is

### 2.2 Voice Input Store (Copy & Adapt)
**Source:** `~/GitHub/VoiceBot/VoiceBotPackage/Sources/VoiceBotFeature/VoiceInputStore.swift`

- [ ] Copy `VoiceInputStore.swift` → `TalkToDoFeature/Stores/`
  - ✅ Observable pattern for iOS 18+
  - ✅ Permission prefetching
  - ✅ Live transcript polling
  - **Adaptations needed:**
    - Remove `liveTranscript` polling (TalkToDo has no live feedback per product doc)
    - Simplify `status` enum to match TalkToDo states
    - Update error messages to TalkToDo branding

### 2.3 Model Services (Copy & Adapt)
**Source Files:**
- `LeapRuntimeAdapter.swift`
- `ModelDownloadService.swift`
- `ModelCatalog.swift`
- `ModelDownloadStore.swift`
- `ModelStorageService.swift`

- [ ] Copy `LeapRuntimeAdapter.swift` → `TalkToDoFeature/Services/LLM/`
  - **Adaptations needed:**
    - Remove streaming (TalkToDo waits for complete response)
    - Add constrained generation support with `@Generatable` macro
    - Add method: `generateStructuredResponse<T: Codable>(prompt:context:type:) async throws -> T`

- [ ] Copy `ModelDownloadService.swift` → `TalkToDoFeature/Services/Model/`
  - ✅ Use as-is

- [ ] Copy `ModelStorageService.swift` → `TalkToDoFeature/Services/Model/`
  - ✅ Use as-is

- [ ] Create `ModelCatalog.swift` in `TalkToDoFeature/Models/`
  - Only include LFM2 models:
    ```swift
    public static let all: [ModelCatalogEntry] = [
        // LFM2-700M (default iOS)
        // LFM2-1.2B (default macOS)
    ]
    ```

- [ ] Copy `ModelDownloadStore.swift` → `TalkToDoFeature/Stores/`
  - ✅ Use as-is

### 2.4 Utilities (Copy)
**Source:** `~/GitHub/VoiceBot/VoiceBotPackage/Sources/VoiceBotFeature/Logger.swift`

- [ ] Copy `Logger.swift` → `TalkToDoFeature/Utilities/`
  - Update category names for TalkToDo events
  - Add events: `node:create`, `node:edit`, `node:delete`, `llm:inference`, `event:append`

---

## Phase 3: Event Sourcing Architecture

### 3.1 Event Model Definitions
- [ ] Create `TalkToDoFeature/Models/Events/NodeEvent.swift`
  ```swift
  @Model
  final class NodeEvent {
      var id: UUID
      var timestamp: Date
      var type: EventType
      var payload: Data // JSON-encoded event data
      var batchId: String // Groups events from same user interaction for undo

      enum EventType: String, Codable {
          case insertNode
          case renameNode
          case deleteNode
          case reparentNode
      }
  }
  ```

- [ ] Create event payload types (using 16-bit hex IDs for LLM efficiency)
  - Node IDs: Generate random 16-bit values, represent as 4-char hex strings (e.g., "a3f2")
  - `InsertNodePayload(nodeId: String, title: String, parentId: String?, position: Int)`
  - `RenameNodePayload(nodeId: String, newTitle: String)`
  - `DeleteNodePayload(nodeId: String)`
  - `ReparentNodePayload(nodeId: String, newParentId: String?, position: Int)`

- [ ] Create utility for ID generation
  ```swift
  struct NodeID {
      static func generate() -> String {
          let value = UInt16.random(in: 0...UInt16.max)
          return String(format: "%04x", value)
      }

      static func isValid(_ id: String) -> Bool {
          id.count == 4 && id.allSatisfy { $0.isHexDigit }
      }
  }
  ```

### 3.2 Snapshot Model (In-Memory)
- [ ] Create `TalkToDoFeature/Models/Node.swift`
  ```swift
  struct Node: Identifiable {
      let id: String  // 4-char hex ID
      var title: String
      var parentId: String?
      var position: Int
      var isCollapsed: Bool = false
      var children: [Node] = []
  }
  ```

- [ ] Create `TalkToDoFeature/Models/NodeTree.swift`
  - Maintains hierarchy: `var rootNodes: [Node]`
  - Methods: `insert()`, `delete()`, `rename()`, `reparent()`, `find()`, `flatten()`
  - **Snapshot Initialization & Sync:**
    ```swift
    @MainActor
    @Observable
    final class NodeTree {
        var rootNodes: [Node] = []
        private var nodeMap: [String: Node] = [:]  // Fast lookup by ID

        // Called on app startup to rebuild from event log
        func rebuildFromEvents(_ events: [NodeEvent]) {
            rootNodes = []
            nodeMap = [:]

            for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
                applyEvent(event)
            }
        }

        // Called every time a new event is appended to the log
        func applyEvent(_ event: NodeEvent) {
            // Decode payload and apply to in-memory tree
            // Update both rootNodes and nodeMap
        }
    }
    ```

### 3.3 Event Store (SwiftData)
- [ ] Create `TalkToDoFeature/Services/EventStore.swift`
  ```swift
  @MainActor
  final class EventStore {
      private let modelContext: ModelContext
      private let nodeTree: NodeTree

      // Append single event or batch (returns batchId for undo)
      func appendEvents(_ events: [NodeEvent], batchId: String) async throws {
          for event in events {
              event.batchId = batchId
              modelContext.insert(event)
              nodeTree.applyEvent(event)  // Keep snapshot in sync
          }
          try modelContext.save()
      }

      func fetchAll() async throws -> [NodeEvent]
      func fetchSince(_ timestamp: Date) async throws -> [NodeEvent]

      // Undo: Remove all events in a batch
      func undoBatch(_ batchId: String) async throws {
          let batch = try fetchEventsByBatchId(batchId)
          for event in batch {
              modelContext.delete(event)
          }
          try modelContext.save()

          // Rebuild snapshot from remaining events
          let allEvents = try await fetchAll()
          nodeTree.rebuildFromEvents(allEvents)
      }

      private func fetchEventsByBatchId(_ batchId: String) throws -> [NodeEvent]
  }
  ```

- [ ] Startup initialization
  - On app launch: `let events = try await eventStore.fetchAll()`
  - Rebuild snapshot: `nodeTree.rebuildFromEvents(events)`
  - After rebuild, snapshot stays in sync via `applyEvent()` on every append

### 3.4 CloudKit Sync Configuration
- [ ] Configure SwiftData CloudKit sync
  - Use `ModelConfiguration(cloudKitDatabase: .private)`
  - Enable automatic sync for `NodeEvent` model
  - Last-write-wins: rely on CloudKit's default conflict resolution

- [ ] Handle sync errors
  - Network unavailable: queue locally
  - Quota exceeded: show user alert
  - Account not signed in: show settings prompt

---

## Phase 4: LLM Integration

### 4.1 System Prompt Design
- [ ] Create `TalkToDoFeature/Prompts/SystemPrompts.swift`
  ```swift
  static let voiceToStructure = """
  You are a voice-to-structure parser for TalkToDo, a hierarchical todo list app.

  Your task: Parse natural speech into hierarchical todo operations.

  Rules:
  1. Extract hierarchy from:
     - Pauses and natural speech rhythm
     - Transition words: "then", "also", "and", "next"
     - Semantic grouping (related tasks = siblings, subtasks = children)

  2. When hierarchy is clear, create parent-child relationships
  3. When hierarchy is ambiguous, create a flat list (all at root level)
  4. Use exact user words for titles (don't rephrase)
  5. Preserve order as spoken

  Examples:
  Input: "Weekend plans. Hiking... pack gear, check weather. Groceries... buy milk, eggs."
  Output: [
    {type: "insertNode", title: "Weekend plans", parentId: null, position: 0},
    {type: "insertNode", title: "Hiking", parentId: <Weekend plans id>, position: 0},
    {type: "insertNode", title: "pack gear", parentId: <Hiking id>, position: 0},
    {type: "insertNode", title: "check weather", parentId: <Hiking id>, position: 1},
    {type: "insertNode", title: "Groceries", parentId: <Weekend plans id>, position: 1},
    {type: "insertNode", title: "buy milk", parentId: <Groceries id>, position: 0},
    {type: "insertNode", title: "buy eggs", parentId: <Groceries id>, position: 1}
  ]

  For node-level commands (when context provided):
  - "add subtasks" → insert children under context node
  - "rename this" → rename context node
  - "move to X" → reparent context node
  """
  ```

### 4.2 Operation Schema with @Generatable
- [ ] Create `TalkToDoFeature/Models/LLM/OperationPlan.swift`
  ```swift
  import LeapSDKConstrainedGeneration

  @Generatable("Plan of operations to perform on todo tree")
  struct OperationPlan: Codable {
      @Guide("List of operations in execution order")
      let operations: [Operation]
  }

  @Generatable("Single operation")
  struct Operation: Codable {
      @Guide("Type: insertNode, renameNode, deleteNode, reparentNode")
      let type: String

      @Guide("4-char hex node ID (e.g. 'a3f2'). Generate random for insert, use existing for others")
      let nodeId: String

      @Guide("Node title for insert/rename")
      let title: String?

      @Guide("4-char hex parent node ID or null for root level")
      let parentId: String?

      @Guide("Position in parent's children (0-based)")
      let position: Int?
  }
  ```

### 4.3 Inference Coordinator
- [ ] Create `TalkToDoFeature/Services/LLM/VoiceInferenceCoordinator.swift`
  ```swift
  actor VoiceInferenceCoordinator {
      private let adapter: LeapRuntimeAdapter
      private var modelRunner: ModelRunner?

      func processTranscript(
          _ transcript: String,
          context: NodeContext?
      ) async throws -> OperationPlan {
          // Build prompt with system prompt + user transcript + optional node context
          // Use constrained generation to get OperationPlan
          // Validate and return
      }
  }
  ```

- [ ] Add validation layer
  - Check operation types are valid
  - Verify UUIDs are properly formatted
  - Ensure parent IDs reference valid nodes (for non-insert ops)

### 4.4 Latency Measurement (Developer Tool)
- [ ] Create `TalkToDoFeature/DevTools/LatencyHarness.swift`
  - Measure ASR duration
  - Measure LLM inference duration
  - Measure UI commit duration
  - Log to console in debug builds
  - Target: ≤1.7s total

---

## Phase 5: UI Components

### 5.1 NodeRow Component
- [ ] Create `TalkToDoFeature/UIComponents/NodeRow.swift`
  ```swift
  struct NodeRow: View {
      let node: Node
      let depth: Int
      let onTap: () -> Void
      let onLongPress: () -> Void
      let onEdit: () -> Void
      let onDelete: () -> Void

      @State private var isLongPressing = false

      var body: some View {
          HStack(spacing: 12) {
              // Indentation spacer
              Color.clear.frame(width: CGFloat(depth) * 20)

              // Chevron (if has children)
              if !node.children.isEmpty {
                  Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .frame(width: 16)
              } else {
                  Color.clear.frame(width: 16)
              }

              // Title
              Text(node.title)
                  .font(.body)
                  .foregroundStyle(isLongPressing ? .blue : .primary)

              Spacer()
          }
          .padding(.vertical, 8)
          .padding(.horizontal, 16)
          .background(isLongPressing ? Color.blue.opacity(0.1) : Color.clear)
          .contentShape(Rectangle())
          .onTapGesture { onTap() }
          .onLongPressGesture(
              minimumDuration: 0.5,
              pressing: { pressing in isLongPressing = pressing },
              perform: { onLongPress() }
          )
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive, action: onDelete) {
                  Label("Delete", systemImage: "trash")
              }
              Button(action: onEdit) {
                  Label("Edit", systemImage: "pencil")
              }
              .tint(.blue)
          }
      }
  }
  ```

**Edge Cases:**
- Deep nesting: cap indentation at depth 5 (100px max)
- Long titles: single line with truncation, `.lineLimit(1)`
- Animation: use `.animation(.spring(duration: 0.3), value: isLongPressing)`
- Haptic feedback: trigger on long-press start (`UIImpactFeedbackGenerator(style: .medium)`)

### 5.2 VoiceInputBar Component
- [ ] Create `TalkToDoFeature/UIComponents/VoiceInputBar.swift`
  ```swift
  struct VoiceInputBar: View {
      @Binding var status: Status
      let onPressStart: () -> Void
      let onPressEnd: () -> Void

      enum Status {
          case idle
          case recording
          case transcribing
          case error(message: String)
          case disabled(message: String)
      }

      var body: some View {
          VStack(spacing: 12) {
              // Error/disabled message
              if let message = feedbackMessage {
                  Text(message)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .transition(.opacity)
              }

              // Mic button
              Circle()
                  .fill(buttonColor)
                  .frame(width: 60, height: 60)
                  .overlay {
                      Image(systemName: "mic.fill")
                          .font(.title2)
                          .foregroundStyle(.white)
                  }
                  .scaleEffect(status == .recording ? 1.1 : 1.0)
                  .shadow(color: glowColor, radius: status == .recording ? 20 : 0)
                  .gesture(
                      LongPressGesture(minimumDuration: .infinity)
                          .onChanged { _ in onPressStart() }
                          .simultaneously(with: DragGesture(minimumDistance: 0)
                              .onEnded { _ in onPressEnd() })
                  )
                  .disabled(!isEnabled)
          }
          .padding(.bottom, 20)
          .animation(.spring(duration: 0.3), value: status)
      }
  }
  ```

**Edge Cases:**
- Permission denied: show `.disabled` state with "Enable microphone in Settings"
- ASR failure: show `.error` state with retry hint
- Long transcription: show `.transcribing` spinner overlay
- Transitions: use `.transition(.opacity.combined(with: .scale))` for glow

### 5.3 EmptyState Component
- [ ] Create `TalkToDoFeature/UIComponents/EmptyStateView.swift`
  ```swift
  struct EmptyStateView: View {
      @State private var breathingScale: CGFloat = 1.0

      var body: some View {
          VStack(spacing: 24) {
              Image(systemName: "mic.circle.fill")
                  .font(.system(size: 80))
                  .foregroundStyle(.blue)
                  .shadow(radius: 10)
                  .scaleEffect(breathingScale)
                  .onAppear {
                      withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                          breathingScale = 1.15
                      }
                  }

              Text("Hold the mic and speak your thoughts")
                  .font(.title3.weight(.medium))

              Text("Try: 'Weekend plans... hiking, groceries, call mom'")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal, 40)
          }
      }
  }
  ```

### 5.4 UndoPill Component
- [ ] Create `TalkToDoFeature/UIComponents/UndoPill.swift`
  ```swift
  struct UndoPill: View {
      let onUndo: () -> Void
      @Binding var isVisible: Bool
      @State private var progress: CGFloat = 1.0

      var body: some View {
          HStack {
              Button(action: onUndo) {
                  HStack {
                      Image(systemName: "arrow.uturn.backward")
                      Text("Undo")
                  }
                  .padding(.horizontal, 16)
                  .padding(.vertical, 10)
                  .background(.regularMaterial)
                  .clipShape(Capsule())
                  .shadow(radius: 4)
              }
              .buttonStyle(.plain)
          }
          .transition(.move(edge: .top).combined(with: .opacity))
          .onAppear {
              withAnimation(.linear(duration: 3.0)) {
                  progress = 0
              }

              Task {
                  try? await Task.sleep(for: .seconds(3))
                  withAnimation { isVisible = false }
              }
          }
      }
  }
  ```

### 5.5 SettingsSheet Component
- [ ] Create `TalkToDoFeature/Views/SettingsView.swift`
  ```swift
  struct SettingsView: View {
      @Bindable var store: SettingsStore

      var body: some View {
          Form {
              Section("Model Selection") {
                  Picker("Model", selection: $store.selectedModelSlug) {
                      Text("LFM2 700M").tag("lfm2-700m")
                      Text("LFM2 1.2B").tag("lfm2-1.2b")
                  }
              }

              Section("Model Management") {
                  ForEach(ModelCatalog.all) { entry in
                      ModelManagementRow(
                          entry: entry,
                          downloadState: store.downloadStates[entry.slug] ?? .notStarted,
                          onDownload: { store.downloadModel(entry) },
                          onDelete: { store.requestDelete(entry) }
                      )
                  }
              }

              #if DEBUG
              Section("Developer") {
                  NavigationLink("System Prompt Editor") {
                      SystemPromptEditor(store: store)
                  }
              }
              #endif
          }
          .navigationTitle("Settings")
      }
  }
  ```

---

## Phase 6: Core Interactions

### 6.1 Global Voice Input Flow
- [ ] Create `TalkToDoFeature/Coordinators/VoiceInputCoordinator.swift`
  ```swift
  @MainActor
  @Observable
  final class VoiceInputCoordinator {
      var voiceStore: VoiceInputStore
      var inferenceCoordinator: VoiceInferenceCoordinator
      var eventStore: EventStore
      var nodeTree: NodeTree

      func handleMicPress() async {
          // 1. Start recording (via voiceStore)
          // 2. On release: stop recording, get transcript
          // 3. Trigger haptic feedback
          // 4. Show glow animation
          // 5. Send to LLM (inferenceCoordinator)
          // 6. Validate operation plan
          // 7. Generate batchId for this user interaction (UUID string)
          // 8. Apply operations to eventStore with batchId
          // 9. NodeTree snapshot auto-updates via applyEvent()
          // 10. Show undo pill
          // 11. Play tick sound
      }
  }
  ```

**Edge Cases:**
- Transcript empty: show error "I didn't catch that"
- LLM returns invalid JSON: show error "Couldn't process that, try again"
- Operation references non-existent parent: create at root level instead
- User presses undo before animation completes: cancel animation, revert events

### 6.2 Node-Level Voice Commands
- [ ] Add `handleNodeLongPress(node: Node)` to coordinator
  - Show recording indicator on node row
  - Pass node context to LLM:
    ```swift
    struct NodeContext {
        let nodeId: UUID
        let title: String
        let parentId: UUID?
        let depth: Int
    }
    ```
  - Apply operations relative to context node

**Edge Cases:**
- "add subtasks" with no clear items → prompt user to be specific
- "delete this" → confirm deletion if node has children
- "move to X" where X doesn't exist → show error or create X first

### 6.3 Undo System
- [ ] Simplified undo using batchId
  ```swift
  @MainActor
  final class UndoManager {
      private var batchHistory: [String] = []  // Stack of batchIds

      func recordBatch(_ batchId: String) {
          batchHistory.append(batchId)
          // Keep only last 20 batches
          if batchHistory.count > 20 {
              batchHistory.removeFirst()
          }
      }

      func undo(eventStore: EventStore) async throws {
          guard let lastBatchId = batchHistory.popLast() else { return }
          try await eventStore.undoBatch(lastBatchId)
      }

      func canUndo() -> Bool {
          !batchHistory.isEmpty
      }
  }
  ```

- [ ] Undo implementation details
  - **Key insight:** Since we have an append-only log with batchId grouping, undo is simple deletion
  - When user triggers undo: delete all events with matching batchId from SwiftData
  - Rebuild snapshot from remaining events (EventStore handles this)
  - Much simpler than inverse operations!
  - Limit undo stack to last 20 batches

### 6.4 Animation and Feedback
- [ ] Add animations to NodeRow
  - Collapse/expand: `.transition(.opacity.combined(with: .scale(scale: 0.95)))`
  - Insert: `.transition(.move(edge: .top).combined(with: .opacity))`
  - Delete: `.transition(.move(edge: .trailing).combined(with: .opacity))`
  - Duration: 0.3s with spring(response: 0.3, dampingFraction: 0.7)

- [ ] Add haptics
  - Mic press start: `.impact(.medium)`
  - Mic release: `.impact(.light)`
  - Operation complete: `.notification(.success)`
  - Error: `.notification(.error)`

- [ ] Add sounds
  - Use `SystemSoundID` for tick sound (system sound 1103)
  - Play on node tree update complete

---

## Phase 7: First Launch Experience

### 7.1 Permission Flow
- [ ] Create `TalkToDoFeature/Views/OnboardingView.swift`
  ```swift
  struct OnboardingView: View {
      @State private var step: OnboardingStep = .welcome

      enum OnboardingStep {
          case welcome
          case modelDownload
          case permissions
          case complete
      }
  }
  ```

- [ ] Implement step-by-step flow
  1. Welcome screen: explain app concept
  2. Model download: show picker (700M vs 1.2B), download with progress
  3. Permissions: request speech + microphone access
  4. Complete: dismiss to main view

**Edge Cases:**
- Download fails: allow retry
- Permissions denied: show settings link
- User closes app mid-download: resume on next launch

### 7.2 Model Download UI
- [ ] Reuse `ModelDownloadStore` from VoiceBot
- [ ] Show progress bar with percentage
- [ ] Show estimated time remaining
- [ ] Allow cancellation
- [ ] Check available storage before starting

### 7.3 Default Model Selection
- [ ] Create `TalkToDoFeature/Utilities/PlatformDefaults.swift`
  ```swift
  enum PlatformDefaults {
      static var defaultModelSlug: String {
          #if os(iOS)
          return "lfm2-700m"
          #elseif os(macOS)
          return "lfm2-1.2b"
          #endif
      }
  }
  ```

---

## Phase 8: Polish & Performance

### 8.1 Latency Optimization
- [ ] Warm-load model at app start
  - Load model in background during onboarding
  - Keep runner alive in memory
- [ ] Reuse Leap conversation context
  - Don't create new conversation per request
  - Reset after errors only
- [ ] Optimize SwiftData queries
  - Index events by timestamp
  - Batch fetch during replay
- [ ] Measure end-to-end latency
  - Target: ASR (500ms) + LLM (1s) + UI (200ms) = 1.7s total
  - Log actual timings in debug builds

### 8.2 Error Handling
- [ ] Network errors (CloudKit sync)
  - Show banner "Changes will sync when online"
  - Queue events locally
- [ ] Model loading errors
  - Show "Model failed to load, try redownloading"
  - Fallback to last known good model
- [ ] ASR errors
  - "Couldn't recognize speech, try again"
  - Offer manual text input (swipe action?)
- [ ] LLM errors
  - "Couldn't process that, please rephrase"
  - Log full error for debugging

### 8.3 Memory Management
- [ ] Limit node tree size
  - Warn at 1000 nodes
  - Suggest archiving at 5000 nodes
- [ ] Unload model when backgrounded (iOS)
  - Reload on foreground
  - Show loading state briefly
- [ ] Clear undo stack on memory warning

### 8.4 Testing Considerations
- [ ] Unit tests
  - Event replay logic
  - Operation validation
  - Node tree mutations
- [ ] Integration tests
  - Full voice→structure flow (mocked LLM)
  - CloudKit sync (mocked)
  - Undo/redo
- [ ] UI tests
  - Onboarding flow
  - Node interactions (tap, long-press, swipe)
  - Settings model management

---

## Implementation Checklist Summary

### ✅ Phase 1: Project Setup (2-3 hours)
- [ ] Xcode project with iOS/macOS targets
- [ ] Swift Package structure
- [ ] Leap SDK integration
- [ ] CloudKit configuration

### ✅ Phase 2: Code Migration (3-4 hours)
- [ ] Copy SpeechRecognitionService (no changes)
- [ ] Copy & adapt VoiceInputStore
- [ ] Copy & adapt LeapRuntimeAdapter (add constrained generation)
- [ ] Copy model download services
- [ ] Copy & update Logger

### ✅ Phase 3: Event Sourcing (4-6 hours)
- [ ] Event models (SwiftData)
- [ ] Snapshot models (in-memory)
- [ ] EventStore service
- [ ] CloudKit sync setup
- [ ] Event replay logic

### ✅ Phase 4: LLM Integration (4-5 hours)
- [ ] System prompt design
- [ ] @Generatable schemas
- [ ] VoiceInferenceCoordinator
- [ ] Validation layer
- [ ] Latency harness

### ✅ Phase 5: UI Components (6-8 hours)
- [ ] NodeRow with collapse/swipe/long-press
- [ ] VoiceInputBar with states
- [ ] EmptyStateView
- [ ] UndoPill
- [ ] SettingsView

### ✅ Phase 6: Core Interactions (5-7 hours)
- [ ] VoiceInputCoordinator
- [ ] Global voice flow
- [ ] Node-level commands
- [ ] UndoManager
- [ ] Animations & haptics

### ✅ Phase 7: First Launch (3-4 hours)
- [ ] OnboardingView
- [ ] Model download flow
- [ ] Permission requests
- [ ] Platform defaults

### ✅ Phase 8: Polish (4-6 hours)
- [ ] Latency optimization
- [ ] Error handling
- [ ] Memory management
- [ ] Testing

**Total Estimated Time: 31-43 hours**

---

## Key Success Metrics
1. **Latency**: 90% of inferences complete within 1.7s
2. **Accuracy**: LLM correctly parses 85%+ of natural speech inputs
3. **Reliability**: 99%+ uptime for on-device features
4. **UX Delight**: Users report "magical" first-use experience
