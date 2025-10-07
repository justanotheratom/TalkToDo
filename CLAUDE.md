# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TalkToDo is a voice-first hierarchical todo app powered by on-device AI. Users hold a microphone button, speak naturally, and watch their thoughts transform into structured hierarchical lists—all processed offline with zero cloud dependency.

**Key Technologies:**
- Swift 6.0+ with SwiftUI
- SwiftData for persistence
- CloudKit Private Database for cross-device sync
- Leap SDK for on-device LLM inference (LFM2 models: 700M/1.2B)
- Apple Speech framework for on-device ASR
- Optional Gemini API for remote processing

## Build Commands

### Opening Project
```bash
cd TalkToDo
open TalkToDo.xcodeproj
```

### Building
```bash
# iOS Simulator (adjust device name to match your installed runtimes)
xcodebuild -scheme TalkToDo-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build

# macOS
xcodebuild -scheme TalkToDo-macOS build
```

### Testing
```bash
# Run all tests
swift test --package-path TalkToDo/TalkToDoPackage

# Run tests in parallel
swift test --package-path TalkToDo/TalkToDoPackage --parallel
```

### Project Generation
When `project.yml` changes, regenerate with:
```bash
tuist generate
```

### Environment Variables
For testing remote Gemini pipelines locally:
```bash
export GEMINI_API_KEY="your-gemini-key"
```
Without this key, remote mode automatically falls back to on-device processing.

## Architecture

### Module Structure
- **TalkToDoPackage/Sources/TalkToDoFeature**: Main feature module containing:
  - `Models/`: Core domain models (Node, NodeEvent, NodeTree, LLMOperation)
  - `Services/`: Business logic (LLM inference, speech recognition, model download, audio capture, processing pipelines)
  - `Stores/`: State management (EventStore, UndoManager, VoiceInputCoordinator, TextInputCoordinator, OnboardingStore, VoiceInputStore)
  - `Views/`: SwiftUI components (MainContentView, NodeRow, NodeListView, MicrophoneInputBar, EmptyStateView, UndoPill, OnboardingView, SettingsView)

- **TalkToDoPackage/Sources/TalkToDoShared**: Cross-target utilities
  - `AppLogger`: Structured logging with categories
  - `NodeID`: 4-character hex ID generator (e.g., "a3f2")
  - `ProcessingMode`: Enum for on-device vs remote processing
  - `GeminiKeyStatus`: API key availability checking

- **iOS/** and **macOS/**: Thin platform wrappers containing app entry points, entitlements, and asset catalogs

### Event Sourcing Architecture

TalkToDo uses event sourcing as its core data architecture:

1. **NodeEvent** (SwiftData model): Append-only event log storing all changes
   - Event types: `insertNode`, `renameNode`, `deleteNode`, `reparentNode`, `toggleCollapse`
   - Each event has: `id`, `timestamp`, `type`, `payload` (JSON), `batchId` (for undo grouping)
   - Synced via CloudKit Private Database with last-write-wins conflict resolution

2. **NodeTree** (in-memory snapshot): Observable state rebuilt from events
   - On startup: `rebuildFromEvents()` replays entire event log
   - At runtime: `applyEvent()` incrementally updates snapshot after each new event
   - This dual approach keeps snapshot perfectly synchronized with the event log

3. **EventStore**: Manages SwiftData persistence and coordinates snapshot updates
   - `append()`: Adds new event to log and updates NodeTree
   - `undoBatch()`: Deletes all events with matching batchId, then rebuilds snapshot

4. **Batch-Based Undo**: All events from one user interaction share the same `batchId`
   - Undo removes entire batch and rebuilds tree from remaining events
   - Simpler than computing inverse operations

### Voice Processing Pipelines

TalkToDo supports two processing modes (toggled in Settings):

1. **On-Device Pipeline** (`OnDeviceVoicePipeline`):
   - `SpeechRecognitionService`: Apple ASR for live transcript
   - `AudioCaptureService`: Records audio to disk
   - `LLMInferenceService`: Loads LFM2 model via Leap SDK, generates structured JSON operations
   - Flow: Audio → Transcript → LLM → Operations → Events

2. **Remote Pipeline** (`GeminiVoicePipeline`):
   - Uses recorded audio file + live transcript from Apple ASR
   - `GeminiAPIClient`: Uploads audio to Gemini's OpenAI-compatible endpoint
   - Gemini performs both transcription and operation generation
   - Falls back to on-device if `GEMINI_API_KEY` is missing or invalid

**Pipeline Factory** (`VoiceProcessingPipelineFactory`): Creates appropriate pipeline based on current mode.

**Coordinators**:
- `VoiceInputCoordinator`: Orchestrates voice → transcript → LLM → events flow
- `TextInputCoordinator`: Handles text-only input (for debugging/testing)
- `OperationExecutor`: Validates and applies LLM operations to EventStore

### LLM Integration Details

- **16-bit Hex Node IDs**: Uses 4-character IDs (e.g., "a3f2") instead of UUIDs to reduce token overhead
- **Structured Output**: LLM generates JSON conforming to `OperationPlan` schema
- **System Prompts**: Context-aware prompts for global commands vs node-specific commands
- **Operations**: `insert_node`, `insert_children`, `reparent_node`, `rename_node`, `delete_node`
- **Model Catalog**: Defines available LFM2 models (700M for iOS, 1.2B for macOS)

## Key Technical Patterns

### Node ID Generation
```swift
let id = NodeID.generate()  // Returns 4-char hex like "a3f2"
```
Traditional UUIDs (36 chars) waste LLM tokens. Compact hex IDs reduce context size.

### Event Application Flow
```swift
// On startup
nodeTree.rebuildFromEvents(allEvents)

// During runtime
try await eventStore.append(event)  // Also calls nodeTree.applyEvent(event)
```

### Undo Implementation
```swift
// Record batch
undoManager.recordBatch(batchId)

// Undo all events with matching batchId
try await eventStore.undoBatch(batchId)
nodeTree.rebuildFromEvents(remainingEvents)
```

### Processing Mode Toggle
```swift
// User toggles in SettingsView
processingMode = .remote(.validKey("sk-..."))  // or .onDevice

// VoiceInputStore creates appropriate pipeline
let pipeline = VoiceProcessingPipelineFactory.createPipeline(
    mode: processingMode,
    // ... other dependencies
)
```

## CloudKit Configuration

- Both iOS and macOS targets require CloudKit capability enabled
- Container identifier must match entitlements files
- Each developer should use unique bundle identifiers (e.g., `com.yourname.talktodo.ios`) to avoid signing conflicts
- Syncs structured app data (NodeEvent records) via CloudKit Private Database
- Last-write-wins conflict resolution for concurrent edits

## Development Workflow

1. **Making Changes**: Primary development happens in `TalkToDoPackage/Sources/`
2. **Adding Services**: Group by feature (place new services alongside peers in `Services/`)
3. **Testing**: Write unit tests in `TalkToDoPackage/Tests/` mirroring source structure
4. **Naming**: Use `TypeNameTests.swift` for test files, `test_specificBehavior` for test methods
5. **Running Tests**: Always run `swift test --parallel` before pushing

## Code Style

- Follow Swift API Design Guidelines
- 4-space indentation
- UpperCamelCase for types, lowerCamelCase for methods/properties
- Async functions use verb phrases (`startRecognition`, `processRecording`)
- Prefer `struct` + protocol design
- Avoid force unwraps
- Keep SwiftUI code declarative

## Voice Processing Notes

- **Live Transcription**: On-device ASR provides real-time transcript during recording
- **Final Processing**: When user releases mic, either on-device LLM or Gemini processes the complete input
- **Audio Recording**: `.caf` format saved to temporary directory for remote processing
- **Validation**: Recording must have minimum duration and non-empty transcript
- **Permissions**: Requires both Speech Recognition and Microphone access

## Testing Gemini Integration

1. Get API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Export in shell: `export GEMINI_API_KEY="your-key"`
3. Or add to Xcode scheme's Run environment variables
4. Enable "Remote (Gemini)" in Settings
5. Without key, app logs warning and falls back to on-device processing

## Common Gotchas

- **Model Downloads**: First launch requires downloading LFM2 model (5-10 minutes)
- **Permissions**: App needs both Speech Recognition and Microphone access
- **Simulator vs Device**: LLM inference is slower on simulator
- **CloudKit Sync**: Requires signing into iCloud on all devices
- **Bundle IDs**: Must be unique per developer to avoid signing conflicts

## Troubleshooting

- "Model not found": Download default model in Settings
- "Microphone access denied": Enable in System Settings → Privacy & Security → Microphone
- CloudKit sync fails: Verify iCloud sign-in and matching container identifiers
- Gemini fallback: Check `GEMINI_API_KEY` is set and valid

## Additional Documentation

- [README.md](README.md): User-facing documentation and getting started guide
- [docs/TalkToDoProduct.md](docs/TalkToDoProduct.md): Product specification and design principles
- [docs/IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md): Phase-by-phase implementation history
- [AGENTS.md](AGENTS.md): Repository-specific guidelines for Claude Code agents
