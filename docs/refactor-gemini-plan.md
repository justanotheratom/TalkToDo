# Voice Processing Refactor Plan

## Goals
- Support runtime switching between on-device voice processing and the remote Gemini 2.5 Flash Lite pipeline.
- Preserve existing on-device flow as the default while enabling a single-step audio → structured operation call for Gemini.
- Maintain live, on-device transcription UI feedback during recording regardless of processing mode.

## Implementation Checklist

### Configuration & Settings
- [ ] Introduce `ProcessingMode` enum (`onDevice`, `remoteGemini`) in `TalkToDoShared/AppConfiguration` with helper copy for UI.
- [ ] Add `VoiceProcessingSettingsStore` persisting the mode via `@AppStorage`/`UserDefaults`, defaulting to `.onDevice`.
- [ ] Update dependency container to supply the settings store and expose it to feature modules.
- [ ] Extend Settings UI with a segmented control bound to the processing mode, including remote-warning text.

### Pipeline Abstractions
- [ ] Create `VoiceProcessingPipeline` protocol in `TalkToDoShared/VoiceProcessing` with `prepareRecording()`, `consumeAudio(url:metadata:)`, `process() async throws -> [NodeOperation]`.
- [ ] Define `RecordingMetadata` struct containing duration, transcript, sample rate, and locale.
- [ ] Refactor existing on-device logic into `OnDeviceVoicePipeline` conforming to the protocol, reusing `LLMInferenceService`.
- [ ] Implement `VoiceProcessingPipelineFactory` that reads the settings store and returns shared pipeline instances.

### Live Transcript Enhancements
- [ ] Port live transcript handling from `~/GitHub/VoiceBot/VoiceBotPackage/Sources/VoiceBotFeature/VoiceInputStore.swift` into TalkToDo’s `VoiceInputStore` (properties, polling task, cleanup).
- [ ] Update `SpeechRecognitionService` to expose `getCurrentTranscript()` for polling interim text.
- [ ] Modify `MicrophoneInputBar` to display live transcript overlay while recording, mirroring VoiceBot behaviour.

### Audio Capture Flow
- [ ] Ensure recording produces a persistent audio file URL; create an `AudioRecorderService` if necessary.
- [ ] Update `VoiceInputStore.finishRecording` to return `RecordingMetadata` including the audio URL and transcript.
- [ ] Guarantee temporary audio files are cleaned up after pipeline completion.

### Remote Gemini Pipeline
- [ ] Implement `GeminiAPIClient` using the OpenAI-compatible endpoint (`https://generativelanguage.googleapis.com/v1beta/openai`).
- [ ] Handle authentication (`Authorization: Bearer`) and request construction for audio input to `gemini-2.5-flash-lite`.
- [ ] Parse responses into existing `NodeOperation` structures, with descriptive errors for non-200 responses.
- [ ] Build `GeminiVoicePipeline` that uploads audio, invokes the API client, applies retry/backoff, and conforms to `VoiceProcessingPipeline`.

### Coordination Logic
- [ ] Update or create `VoiceInputCoordinator` to gather `RecordingMetadata`, select pipeline via factory, and dispatch resulting operations to reducers.
- [ ] Add telemetry/logging for mode selection, completion latency, and error diagnostics.
- [ ] Implement fallback behaviour: if remote pipeline fails, fall back to on-device processing and surface UI error.

### Testing & Validation
- [ ] Add unit tests for settings store persistence, pipeline selection, and Gemini response parsing.
- [ ] Create tests for live transcript state updates and coordinator error handling.
- [ ] Update or add UI tests for settings toggle and transcript overlay visibility.
- [ ] Manually verify both pipelines on iOS/macOS builds; confirm no orphaned temp files.

### Documentation & Developer Guidance
- [ ] Update `AGENTS.md` with new setup steps (Gemini API key, settings toggle) and remote mode caveats.
- [ ] Document telemetry expectations and troubleshooting tips for remote latency/failures.
