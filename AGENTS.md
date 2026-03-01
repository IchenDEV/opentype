# OpenType — Agent Guidelines

## Project Overview

OpenType is a macOS menu bar voice input app built with Swift 6 / SwiftUI / AppKit. It runs on macOS 26+ (Apple Silicon only) and uses WhisperKit and MLX-LM for local inference, with optional remote LLM support.

## Architecture

- **Pure Swift Package** (no .xcodeproj) — everything is driven by `Package.swift`
- **Single executable target** named `OpenType` under `Sources/`
- **Functional style preferred** — avoid unnecessary classes; use enums, structs, and free functions where possible
- **File size**: each file should stay under 300 lines (ideally ~100 lines); split when growing

## Module Map

| Directory | Responsibility |
|---|---|
| `App/` | Entry point (`OpenTypeApp`), `AppState` (observable), `VoicePipeline` (coordinator), `AppIcon` |
| `Audio/` | `AudioCaptureManager` (AVAudioEngine), `SoundPlayer` |
| `Config/` | `AppSettings` (UserDefaults-backed), `ModelCatalog`, `RemoteModelConfig`, `Loc` (localization helper), `Log` |
| `Hotkey/` | `HotkeyManager` — CGEvent tap for global keyboard shortcuts |
| `LLM/` | `LLMEngine` (MLX local), `RemoteLLMClient` (OpenAI + Anthropic formats), `PromptBuilder` |
| `Output/` | `TextInserter` — Accessibility API text injection with clipboard fallback |
| `Processing/` | `TextProcessor`, `InputHistory`, `MemoryStore`, `PersonalDictionary` |
| `Screen/` | `ScreenOCR` — ScreenCaptureKit + Vision framework |
| `Speech/` | `SpeechEngineProtocol`, `AppleSpeechEngine`, `WhisperEngine` |
| `UI/` | All SwiftUI views: MenuBar, Settings (tabbed), Onboarding, Overlay HUD, History, Models, About |
| `Resources/` | `en.lproj/` and `zh-Hans.lproj/` Localizable.strings, Sounds/, AppIcon.png |

## Key Patterns

- **`@MainActor`** is used for all UI-touching code; background work uses `Task { }` and `actor`
- **Localization**: all user-facing strings go through `L("key")` (defined in `Loc.swift`), with entries in both `en.lproj` and `zh-Hans.lproj`
- **Settings persistence**: `AppSettings` uses `@Published` + Combine `sink` to auto-persist to `UserDefaults`
- **Remote LLM**: `RemoteLLMClient` dispatches to OpenAI-format (`/chat/completions`) or Anthropic-format (`/messages`) based on `provider.apiFormat`
- **Text processing**: no hardcoded filler-word removal — the LLM handles all contextual cleanup via the system prompt

## Build & Release

- **Dev build**: `swift build` or open `Package.swift` in Xcode
- **Release build**: `bash scripts/build-app.sh` — uses `xcodebuild` (required for Metal shader bundling), then assembles .app and .dmg
- **CI**: `.github/workflows/release.yml` — builds on macOS, signs, optionally notarizes, publishes to GitHub Releases
- **Icon**: `scripts/generate-icon.swift` loads `Sources/Resources/AppIcon.png`, crops transparent edges, generates `.icns`

## Coding Conventions

- Swift 6 with `.swiftLanguageMode(.v5)` for compatibility
- Prefer `enum` namespaces (e.g., `enum PromptBuilder { static func ... }`) over classes for stateless logic
- Mark `@MainActor` explicitly on types that touch UI or AppKit
- Use structured concurrency (`async/await`, `Task`, `actor`) — avoid GCD
- All logging through `Log.info()` / `Log.error()` (defined in `Config/Log.swift`)
- Comments: only non-obvious intent, no narrating code

## Common Pitfalls

- **Metal shaders**: `swift build` does NOT bundle `.metallib` files — always use `xcodebuild` for release builds
- **TCC permissions**: ad-hoc signed builds lose permissions on every rebuild; use a signing certificate for stable development
- **Screen Recording permission**: use `SCShareableContent.current` async check, not `CGPreflightScreenCaptureAccess()` alone
- **Apple Speech**: defer `SFSpeechRecognizer.requestAuthorization` until actually needed, not at app launch
