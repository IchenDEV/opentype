# OpenType HTTP Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the Phase 1 `OpenTypeService` through a local-only HTTP developer API with JSON responses and Server-Sent Events snapshots.

**Architecture:** Add a small `Network.framework` HTTP server under `Sources/Integration/` that binds only to `127.0.0.1` while the developer interface is enabled. The server is a thin transport adapter: it validates bearer tokens, maps REST routes to `OpenTypeService`, encodes JSON/SSE, and starts/stops from `AppDelegate` based on `AppSettings`.

**Tech Stack:** Swift 6, Foundation, Network.framework, AppKit app lifecycle, XCTest contract tests by inspection in this environment.

---

## Scope

Included:

- Local HTTP server bound to `127.0.0.1:<developerHTTPPort>`.
- Bearer-token validation against `AppSettings.developerHTTPToken`.
- Routes:
  - `POST /v1/sessions`
  - `GET /v1/sessions/{id}/events`
  - `POST /v1/sessions/{id}/recording/start`
  - `POST /v1/sessions/{id}/recording/stop`
  - `POST /v1/sessions/{id}/cancel`
- JSON response/error encoding.
- SSE response encoding for the current event snapshot.
- App startup integration that starts/stops the HTTP server when the developer interface setting changes.

Deferred:

- Real microphone recording through `InputSessionCoordinator`.
- Long-lived live SSE streams that push future events as they arrive.
- CLI bridge.
- XPC service and code-signature registration.
- Caller-provided audio upload.

## File Structure

- Create `Sources/Integration/IntegrationHTTPTypes.swift`
  - Request parsing, HTTP response, route types, and helpers.
- Create `Sources/Integration/IntegrationHTTPServer.swift`
  - `NWListener` lifecycle, connection handling, and route dispatch into `OpenTypeService`.
- Modify `Sources/Integration/OpenTypeService.swift`
  - Add a transport-safe `completeSession` mapping for recording stop until real recording exists.
- Modify `Sources/App/OpenTypeApp.swift`
  - Hold an `OpenTypeService`, `IntegrationClientRegistry`, and `IntegrationHTTPServer`; start/stop with settings.
- Create `Tests/OpenTypeTests/IntegrationHTTPTests.swift`
  - Tests request parsing, auth parsing, route matching, JSON/SSE encoding.

## Task 1: HTTP Parsing and Encoding Types

**Files:**
- Create: `Sources/Integration/IntegrationHTTPTypes.swift`
- Test: `Tests/OpenTypeTests/IntegrationHTTPTests.swift`

- [ ] Write tests for bearer-token extraction, route parsing, JSON response encoding, and SSE encoding.
- [ ] Implement `IntegrationHTTPRequest`, `IntegrationHTTPResponse`, `IntegrationHTTPRoute`, and `IntegrationSSE`.
- [ ] Run `swift build`.
- [ ] Attempt `swift test --filter IntegrationHTTPTests` and record the local XCTest result.
- [ ] Commit with `Add integration HTTP transport types`.

## Task 2: HTTP Server Dispatch

**Files:**
- Create: `Sources/Integration/IntegrationHTTPServer.swift`
- Modify: `Sources/Integration/OpenTypeService.swift`
- Test: `Tests/OpenTypeTests/IntegrationHTTPTests.swift`

- [ ] Add tests for dispatching each route against a fake/in-memory service where practical, or for handler-level request/response behavior.
- [ ] Implement an `@MainActor final class IntegrationHTTPServer` using `NWListener` on `.tcp` with host `127.0.0.1`.
- [ ] For every authorized HTTP request, approve/register the current `IntegrationClient.localHTTP(tokenID:)` before calling `OpenTypeService`.
- [ ] Map routes:
  - `POST /v1/sessions`: decode `InputSessionRequest`, create session, return session JSON.
  - `GET /v1/sessions/{id}/events`: return `text/event-stream` snapshot from `OpenTypeService.snapshotEvents`.
  - `POST /v1/sessions/{id}/recording/start`: call `startRecording`.
  - `POST /v1/sessions/{id}/recording/stop`: until real recording exists, call `beginProcessing` then `completeSession(finalText: nil)`.
  - `POST /v1/sessions/{id}/cancel`: call `cancel`.
- [ ] Return stable JSON errors for `IntegrationError`.
- [ ] Run `swift build`.
- [ ] Commit with `Add local integration HTTP server`.

## Task 3: App Lifecycle Wiring

**Files:**
- Modify: `Sources/App/OpenTypeApp.swift`
- Test: compile/build verification.

- [ ] Add `IntegrationClientRegistry`, `OpenTypeService`, and optional `IntegrationHTTPServer` properties to `AppDelegate`.
- [ ] On launch, start the server only if `developerInterfaceEnabled` is true.
- [ ] Observe `developerInterfaceEnabled`, `developerHTTPPort`, and `developerHTTPToken`; restart/stop the server as needed.
- [ ] Do not bind HTTP while developer interface is disabled.
- [ ] Run `swift build`.
- [ ] Commit with `Start integration HTTP server from app settings`.

## Task 4: Verification and Review

**Files:**
- No new files.

- [ ] Run `swift build`.
- [ ] Attempt relevant `swift test --filter ...` commands and record the XCTest environment blocker if present.
- [ ] Run `git diff --check`.
- [ ] Request final review for the HTTP slice.
