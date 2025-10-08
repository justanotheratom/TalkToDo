<!-- bb907403-31a1-48d6-a7cb-a0e72b9b34dc a7f4319f-e182-4ffc-b9d6-ce225b233168 -->
# Introduce Model Configs and AI Programs

## Overview

Refactor the remote processing architecture to support multiple LLM providers and prompt variations through model configurations and AI programs. Enable users to select different configs for voice and text processing modes, with API keys stored securely in keychain or environment variables.

## 1. Create Keychain Service for Secure Storage

Create `TalkToDoShared/KeychainService.swift`:

- Implement standard keychain operations (save, read, delete) using `SecItem` APIs
- Use service identifier format: `com.talktodo.apikey.<keyName>`
- Support both iOS and macOS keychain access groups
- Handle keychain errors gracefully

## 2. Define Model Configuration System

Create `TalkToDoShared/Configuration/ModelConfig.swift`:

- Define `ModelProvider` enum (gemini, openai, anthropic, etc.)
- Define `ModelConfig` struct with:
- `id: String` (unique identifier like "gemini-flash-lite")
- `provider: ModelProvider`
- `displayName: String` (user-friendly name)
- `modelIdentifier: String` (API model name like "gemini-2.5-flash-lite")
- `apiKeyName: String` (env var and keychain key name like "GEMINI_API_KEY")
- `baseURL: URL` (API endpoint)
- `supportsAudio: Bool` (whether it accepts audio input)
- `supportsText: Bool` (whether it accepts text input)
- Create `ModelConfigCatalog` with hardcoded configs:
- Gemini 2.5 Flash Lite (current)
- Gemini 2.0 Flash (future)
- OpenAI GPT-4o (example)
- Add computed properties for `voiceCapableConfigs` and `textCapableConfigs`
- Implement `APIKeyResolver` protocol to fetch keys from environment or keychain with fallback logic

## 3. Create AI Program System

Create `TalkToDoFeature/Services/Programs/` directory structure:

- Create `AIProgram.swift` protocol defining:
- `id: String`
- `displayName: String`
- `modelConfig: ModelConfig`
- `systemPrompt: String`
- `inputType: ProgramInputType` (audio, text)
- Create `ProgramPrompts.swift` with prompt templates stored as string resources:
- `voiceToStructureV1` (current Gemini prompt from `GeminiAPIClient.swift:141-157`)
- `voiceToStructureV2` (alternative prompt with different instructions)
- `textToStructureV1` (optimized for text input)
- Create concrete program implementations:
- `GeminiVoiceProgram` (Gemini Flash Lite + voiceToStructureV1)
- `GeminiTextProgram` (Gemini Flash Lite + textToStructureV1)
- Add OpenAI examples for future extensibility
- Create `ProgramCatalog` with all available programs organized by input type

## 4. Refactor Processing Settings Store

Update `TalkToDoShared/Configuration/ProcessingMode.swift`:

- Rename `VoiceProcessingSettingsStore` to `ProcessingSettingsStore`
- Replace `remoteAPIKey` with config selection approach:
- Add `selectedVoiceProgramId: String?` (persisted in UserDefaults)
- Add `selectedTextProgramId: String?` (persisted in UserDefaults)
- Remove Gemini-specific fields
- Add methods:
- `updateSelectedVoiceProgram(id: String?)`
- `updateSelectedTextProgram(id: String?)`
- `resolvedVoiceProgram() -> AIProgram` (returns selected or default)
- `resolvedTextProgram() -> AIProgram` (returns selected or default)
- `storeAPIKey(for keyName: String, value: String)` (saves to keychain)
- `deleteAPIKey(for keyName: String)` (removes from keychain)
- `resolveAPIKey(for keyName: String) -> String?` (checks env then keychain)
- Migrate existing Gemini key from UserDefaults to keychain on init

## 5. Refactor Generic API Client

Rename and refactor `GeminiAPIClient.swift` to `RemoteAPIClient.swift`:

- Make it provider-agnostic by accepting `ModelConfig` and `systemPrompt` in configuration
- Remove hardcoded model name ("gemini-2.5-flash-lite") at line 164
- Remove hardcoded system prompt (lines 141-158)
- Update `Configuration` struct to include:
- `modelConfig: ModelConfig`
- `systemPrompt: String`
- `apiKey: String`
- Rename protocol from `GeminiClientProtocol` to `RemoteAPIClientProtocol`
- Keep request/response format compatible with OpenAI-style APIs
- Update error messages to be provider-neutral

## 6. Update Pipeline Implementations

Refactor `GeminiVoicePipeline.swift` and `GeminiTextPipeline.swift`:

- Rename to `RemoteVoicePipeline.swift` and `RemoteTextPipeline.swift`
- Accept `AIProgram` instead of generic client in initializer
- Construct `RemoteAPIClient` internally using program's config and prompt
- Update error logging to reference program ID instead of "gemini"

## 7. Modernize Pipeline Factory

Update `VoiceProcessingPipelineFactory.swift`:

- Remove Gemini-specific caching (`cachedGeminiVoicePipeline`, etc.)
- Implement program-based pipeline construction:
- `voicePipeline(for program: AIProgram) -> AnyVoiceProcessingPipeline`
- `textPipeline(for program: AIProgram) -> AnyTextProcessingPipeline`
- Add API key resolution logic using `APIKeyResolver`
- Cache pipelines by program ID instead of hardcoded keys
- Update `currentPipeline()` to use `settingsStore.resolvedVoiceProgram()`
- Handle missing API keys gracefully with helpful error messages

## 8. Update RemoteSettingsView UI

Refactor `RemoteSettingsView.swift`:

- Replace hardcoded "Gemini 2.5 Flash Lite" display with dynamic program selection
- Add `Picker` for selecting voice processing program from `ProgramCatalog.voicePrograms`
- Add `Picker` for selecting text processing program from `ProgramCatalog.textPrograms`
- Display selected program's model config info (provider, model name)
- Show API key status for the currently selected program's `apiKeyName`
- Add paste/clear buttons per selected config (not per provider)
- Show all unique API keys needed across selected programs
- Update help text to be provider-agnostic

## 9. Update Test Infrastructure

Update `GeminiTextIntegrationTests.swift` to become `ProgramIntegrationTests.swift`:

- Iterate through all programs in `ProgramCatalog`
- For each program, check if API key is available via `TestEnvironment`
- Skip tests for programs without API keys (XCTSkip)
- Run standard test cases against each available program:
- Simple grocery list creation
- Hierarchical task parsing
- Empty input handling
- Context-aware operations (using eventLog and nodeSnapshot)
- Add helper to update `TestEnvironment.swift` to resolve keys by name
- Verify operations match expected structure regardless of provider
- Log which program/config was tested for debugging

## 10. Migration and Compatibility

Update initialization and migration:

- In `ProcessingSettingsStore.init()`, migrate existing Gemini key from UserDefaults to keychain
- Set default programs if none selected:
- Voice: first available voice-capable program (Gemini Flash Lite)
- Text: first available text-capable program (Gemini Flash Lite)
- Update `MainContentView.swift` to use new `ProcessingSettingsStore` APIs
- Update `OnboardingView.swift` API key step to work with selected program config
- Ensure backward compatibility: existing users with Gemini keys continue working

## Key Files to Modify

- `TalkToDoShared/Configuration/ProcessingMode.swift` (ProcessingSettingsStore)
- `TalkToDoFeature/Services/Gemini/GeminiAPIClient.swift` → `RemoteAPIClient.swift`
- `TalkToDoFeature/Services/Gemini/GeminiVoicePipeline.swift` → `RemoteVoicePipeline.swift`
- `TalkToDoFeature/Services/Gemini/GeminiTextPipeline.swift` → `RemoteTextPipeline.swift`
- `TalkToDoFeature/Services/VoiceProcessingPipelineFactory.swift`
- `TalkToDoFeature/Views/RemoteSettingsView.swift`
- `TalkToDoFeatureTests/GeminiTextIntegrationTests.swift` → `ProgramIntegrationTests.swift`

## New Files to Create

- `TalkToDoShared/KeychainService.swift`
- `TalkToDoShared/Configuration/ModelConfig.swift`
- `TalkToDoFeature/Services/Programs/AIProgram.swift`
- `TalkToDoFeature/Services/Programs/ProgramPrompts.swift`
- `TalkToDoFeature/Services/Programs/ProgramCatalog.swift`
- `TalkToDoFeature/Services/Programs/GeminiVoiceProgram.swift`
- `TalkToDoFeature/Services/Programs/GeminiTextProgram.swift`

### To-dos

- [x] Create KeychainService for secure API key storage
- [x] Define ModelConfig system with provider catalog and API key resolver
- [x] Create AI program system with prompts and program catalog
- [x] Refactor ProcessingSettingsStore for program selection and keychain integration
- [x] Refactor GeminiAPIClient to provider-agnostic RemoteAPIClient
- [x] Update pipeline implementations to use AI programs
- [x] Modernize VoiceProcessingPipelineFactory for program-based construction
- [x] Update RemoteSettingsView with program selection UI
- [x] Refactor tests to run against all AI programs programmatically
- [x] Implement migration logic and ensure backward compatibility
