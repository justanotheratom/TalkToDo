# Repository Guidelines

## Project Structure & Module Organization
Primary development happens inside `TalkToDo/TalkToDoPackage`. `TalkToDoFeature` contains domain models, voice and LLM services, state stores, and SwiftUI views; `TalkToDoShared` holds cross-target utilities such as logging and ID helpers. The `iOS/` and `macOS/` folders host thin platform wrappers plus entitlements and asset catalogs. Additional planning material lives under `docs/`, and the root `project.yml` feeds Tuist when regenerating the Xcode project.

## Build, Test, and Development Commands
Run `open TalkToDo/TalkToDo.xcodeproj` to work in Xcode. For scripted builds use:
```bash
xcodebuild -scheme TalkToDo-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme TalkToDo-macOS build
swift test --package-path TalkToDo/TalkToDoPackage
```
Use the simulator destination that matches your installed runtimes. Regenerate project files with `tuist generate` when `project.yml` changes.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines with 4-space indentation. Group related Swift files by feature (e.g., keep new services alongside peers under `Services/`). Types use UpperCamelCase, methods and properties use lowerCamelCase, and async functions should include verb phrases (`startRecognition`). Prefer `struct` + protocol design, avoid force unwraps, and keep platform code declarative SwiftUI.

## Testing Guidelines
Unit tests live in `TalkToDo/TalkToDoPackage/Tests`, mirroring the feature directory layout. Name test files after the production type plus `Tests` suffix and use `func test_` prefixes for clarity (`NodeTreeReducerTests`, `test_applyInsertEvent`). Run `swift test --parallel` locally before pushing, and target high coverage on event-sourcing logic and LLM orchestration boundaries.

## Commit & Pull Request Guidelines
Use short, imperative commit subjects around 60 characters (e.g., “Add VoiceBot input bar”) and extend with context in the body when needed. PRs should link relevant issues, describe user-facing changes, and include screenshots or screen recordings for UI updates. Confirm you ran the iOS simulator happy path and package tests, and call out any configuration steps (CloudKit IDs, model downloads) reviewers must repeat.

## Security & Configuration Tips
Keep bundle identifiers (`com.talktodo.*`) unique per developer to avoid signing conflicts. CloudKit requires aligning the entitlements in both platform targets; document custom containers in the PR. Store large language model binaries outside the repo and rely on the in-app downloader to avoid leaking licensed assets.
