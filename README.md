# TalkToDo

> **Voice-first hierarchical todo app powered by on-device AI**

Hold the mic, speak naturally, and watch your thoughts transform into structured, hierarchical lists — all processed offline with zero cloud dependency.

## Features

- **Natural Voice Input**: Speak like a human, see structure like an outliner
- **On-Device AI**: LFM2 models (700M on iOS, 1.2B on macOS) via Leap SDK
- **Offline-First**: Speech recognition, LLM inference, and sync all happen locally
- **Event Sourcing**: Append-only log with in-memory snapshot for instant UI updates
- **CloudKit Sync**: Seamless cross-device sync via CloudKit Private Database
- **Batch Undo**: Simple undo via batch deletion and snapshot rebuild
- **Minimal UI**: Clean, focused interface with subtle animations

## Requirements

- iOS 18.0+ or macOS 15.7+
- Xcode 16.0+
- Swift 5.9+
- Active Apple Developer account (for CloudKit)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/TalkToDo.git
cd TalkToDo
```

### 2. Open the Project

```bash
cd TalkToDo
open TalkToDo.xcodeproj
```

### 3. Configure CloudKit

1. In Xcode, select the iOS or macOS target
2. Go to "Signing & Capabilities"
3. Update the bundle identifier to your own (e.g., `com.yourname.talktodo.ios`)
4. Ensure iCloud capability is enabled with CloudKit checked
5. Verify the container identifier matches your entitlements file

### 4. Build and Run

- **iOS**: Select an iOS device or simulator and press Cmd+R
- **macOS**: Select "My Mac" and press Cmd+R

## Architecture

### Event Sourcing

- **NodeEvent**: SwiftData model storing append-only events (insert, rename, delete, reparent)
- **NodeTree**: In-memory snapshot rebuilt from events on startup, updated incrementally at runtime
- **EventStore**: Manages persistence and coordinates snapshot updates
- **UndoManager**: Groups events by batchId for simple undo

### LLM Integration

- **LLMInferenceService**: Loads LFM2 models and generates structured JSON operations
- **System Prompts**: Context-aware prompts for global vs node-level commands
- **16-bit Hex IDs**: 4-character node IDs (e.g., "a3f2") for LLM efficiency

### Voice Input

- **SpeechRecognitionService**: On-device ASR via Apple's Speech framework
- **VoiceInputStore**: Manages recording state and permissions
- **VoiceInputCoordinator**: Orchestrates voice → transcript → LLM → events flow

### UI Components

- **NodeRow**: Hierarchical node with tap/long-press/swipe gestures
- **MicrophoneInputBar**: Press-and-hold mic button
- **EmptyStateView**: Pulsing mic icon with usage hint
- **UndoPill**: Temporary overlay for quick undo
- **OnboardingView**: First-launch flow for model download and permissions

## Usage

### Creating Nodes

1. Press and hold the microphone button
2. Speak naturally: *"Thanksgiving prep... groceries: turkey, cranberries... house: clean guest room"*
3. Release when done
4. Watch the hierarchical structure appear

### Node Interactions

- **Tap**: Collapse/expand children
- **Long-Press**: Speak a context-aware command (e.g., "add buy milk")
- **Swipe Left**: Reveal Edit and Delete actions

### Undo

- After creating nodes, an undo pill appears briefly
- Tap to undo the last operation (removes entire batch)

### Settings

- Tap the gear icon to access settings
- Download or delete LFM2 models (700M or 1.2B)
- Switch between models (requires re-download)

## Project Structure

```
TalkToDo/
├── docs/
│   ├── TalkToDoProduct.md        # Product specification
│   └── implementation.md          # Implementation plan
├── TalkToDo/                      # Xcode workspace
│   ├── iOS/                       # iOS app target
│   ├── macOS/                     # macOS app target
│   └── TalkToDoPackage/           # Swift Package
│       └── Sources/
│           ├── TalkToDoFeature/   # Main feature module
│           │   ├── Models/        # Node, NodeEvent, LLMOperation
│           │   ├── Services/      # LLM, Speech, Download, Storage
│           │   ├── Stores/        # EventStore, UndoManager, Coordinators
│           │   └── Views/         # SwiftUI components
│           └── TalkToDoShared/    # Shared utilities (AppLogger, NodeID)
└── README.md
```

## Technical Highlights

### 16-bit Hex Node IDs

Traditional UUIDs (36 chars) waste LLM tokens. TalkToDo uses 4-character hex IDs:

```swift
let id = NodeID.generate()  // "a3f2"
```

This reduces token overhead and makes IDs easier for the LLM to generate and reference.

### Batch-Based Undo

Instead of computing inverse operations, TalkToDo groups events by `batchId`:

```swift
// All events from one voice input share the same batchId
undoManager.recordBatch(batchId)

// Undo deletes all events with matching batchId and rebuilds snapshot
try await eventStore.undoBatch(batchId)
nodeTree.rebuildFromEvents(allEvents)
```

### Snapshot Sync

- **Startup**: Fetch all events → `rebuildFromEvents()`
- **Runtime**: Append event → `applyEvent()` (incremental update)

This keeps the snapshot in sync with the log without drift.

## Troubleshooting

### "Model not found"

- Go to Settings and download the default model (LFM2 700M on iOS, 1.2B on macOS)
- First download can take 5-10 minutes depending on connection

### "Microphone access denied"

- Open System Settings → Privacy & Security → Microphone
- Enable access for TalkToDo

### CloudKit sync not working

- Ensure you're signed into iCloud on all devices
- Verify CloudKit capability is enabled in Xcode
- Check that container identifiers match across targets

## Roadmap

- [ ] Structured streaming inference (if Leap SDK supports)
- [ ] Smart corrections via follow-up voice
- [ ] Adaptive animation timing based on confidence
- [ ] Export to Markdown/JSON
- [ ] Widgets for quick voice capture

## License

MIT License - see LICENSE file for details

## Acknowledgments

- **Leap SDK** by [Liquid AI](https://liquid.ai) for on-device LLM inference
- **Apple Speech Framework** for privacy-first speech recognition
- Built with inspiration from the voice-to-structure interaction category

---

**Hold the mic. Speak your thoughts. See structure appear.**
