# Input Context Memory Upgrade

**Date:** 2026-06-13
**Status:** Approved for implementation
**Scope:** Upgrade OpenType input history and memory so each output can remember when it happened, which app was active, what context was visible, and what text was produced.

## Goals

1. Preserve the existing `InputHistory` storage path and extend it with contextual metadata.
2. Capture app, window, mode, language, source, and screen summary for menu bar and integration inputs.
3. Use same-app and same-window history as prompt context before falling back to recent global history.
4. Show app and context metadata in the History tab without adding a second memory store.
5. Keep older `input_history.json` files readable.

## Non-goals

- No separate memory database.
- No semantic embedding search.
- No app-level analytics dashboard.
- No long-term screen capture archive.

## Architecture

The existing `InputRecord` remains the single persisted unit for history and memory. A new `InputContext` value is attached to each record and holds app identity, window title, screen summary, output mode, input language, and source. All new fields are optional or have decode defaults so older history files continue loading.

`VoicePipeline` captures the frontmost app when recording stops and stores the context after insertion. `InputSessionCoordinator` records integration outputs in the same history path with source metadata. `MemoryStore` ranks recent records by matching bundle id and window title, then adds recent fallback records up to a small limit.

## Data Shape

`InputContext`:

- `appName`
- `bundleIdentifier`
- `windowTitle`
- `screenContext`
- `outputMode`
- `inputLanguage`
- `source`

`InputSource`:

- `menuBar`
- `integration`

`InputRecord` keeps `rawText`, `processedText`, char counts, `wasProcessed`, and optional `context`.

## Capture Rules

- App name and bundle id come from the target app passed to insertion, falling back to the current frontmost app.
- Window title comes from the app's accessibility focused window when available.
- Screen summary reuses the OCR text already captured for the current request and is truncated before persistence.
- Direct mode stores history but does not use memory in LLM prompts.
- Smart Format and Voice Command can use memory when `enableMemory` is on.
- Deferred Smart Format updates the latest record while keeping the same context.

## History UI

The History tab keeps its compact list layout. Each row adds a small metadata line for app, mode, and time. Search matches processed text, raw text, app name, bundle id, and window title.

## Compatibility

Existing records without `context` decode successfully. Missing `rawCharCount` or `processedCharCount` can be derived from stored text during decoding.

## Verification

- Unit tests cover context decoding, metadata search, and memory ranking.
- Policy tests cover memory usage for Smart Format, Voice Command, and Direct mode.
- Build and focused tests must pass before completion.
