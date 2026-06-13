# Input Context Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend OpenType input memory so each saved output records time, app, window, mode, language, source, and screen context, then uses that metadata for prompt context and history search.

**Architecture:** Reuse `InputHistory` as the only persisted store. Add small context models under `Sources/Processing/`, pass context through `VoicePipeline` and `InputSessionCoordinator`, and keep prompt assembly in `MemoryStore`.

**Tech Stack:** Swift 6 package, SwiftUI, AppKit Accessibility, XCTest, existing JSON history persistence.

---

## File Structure

- Create `Sources/Processing/InputContext.swift`
  - Owns `InputContext`, `InputSource`, context truncation, and target-app capture helpers.
- Modify `Sources/Processing/InputHistory.swift`
  - Adds optional context to `InputRecord`, compatibility decoding, metadata search helper, and context-preserving record replacement.
- Modify `Sources/Processing/MemoryStore.swift`
  - Adds ranked recent context using current `InputContext`.
- Modify `Sources/App/VoicePipeline+Processing.swift`
  - Saves final insertion context and passes memory context into Smart Format.
- Modify `Sources/App/VoicePipeline+Replacement.swift`
  - Saves quick insertion context, uses memory for background formatting, and keeps context during replacement.
- Modify `Sources/Integration/InputSessionCoordinator.swift`
  - Saves integration outputs with source context.
- Modify `Sources/UI/HistoryStatsView.swift`
  - Uses search helper and row metadata display.
- Modify `Sources/App/VoicePipelinePolicy.swift`
  - Allows memory for Smart Format and Voice Command, skips Direct.
- Add or extend tests in `Tests/OpenTypeTests/PromptAndProcessingTests.swift` and `Tests/OpenTypeTests/VoicePipelinePolicyTests.swift`.

## Tasks

### Task 1: Context Models and History Compatibility

- [ ] Add `InputContext` and `InputSource` with stable Codable raw values.
- [ ] Add optional `context` to `InputRecord`.
- [ ] Add a compatibility decoder for old records without `context`.
- [ ] Add `matchesSearch(_:)` so UI search does not duplicate record-field knowledge.
- [ ] Test decoding old JSON and matching context fields.

### Task 2: Memory Ranking

- [ ] Change `MemoryStore.recentContext` to accept an optional current context.
- [ ] Rank same bundle id first, same window title second, then recent fallback.
- [ ] Format memory lines with time, app, and window labels.
- [ ] Test ranking and direct-mode policy behavior.

### Task 3: Menu Bar Pipeline Capture

- [ ] Capture `InputContext` before final insertion and save it with `InputHistory`.
- [ ] Pass ranked memory context to Smart Format and Voice Command.
- [ ] For deferred Smart Format, save quick context and preserve it when replacement succeeds.
- [ ] Reuse existing OCR text and truncate before persistence.

### Task 4: Integration Capture

- [ ] Add integration source context to `InputSessionCoordinator`.
- [ ] Save records for direct, processed, and command integration outputs.
- [ ] Include mode and input language in saved context.

### Task 5: History UI

- [ ] Use `record.matchesSearch(searchText)` for filtering.
- [ ] Show app, window, mode, and time metadata below each history item.
- [ ] Keep `HistoryStatsView.swift` under 300 lines by moving small formatting helpers into a focused file if needed.

### Task 6: Verification

- [ ] Run focused policy and processing tests.
- [ ] Run `swift build`.
- [ ] Run `bash scripts/ci-basic-checks.sh`.
