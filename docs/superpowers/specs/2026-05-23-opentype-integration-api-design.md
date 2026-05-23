# OpenType integration API

**Date:** 2026-05-23
**Status:** Draft, awaiting user review
**Scope:** Local developer interface for external apps to reuse OpenType's voice input, transcription, and text processing capabilities without bundling models again.

## Goals

1. Let other local apps call OpenType and receive text results instead of embedding WhisperKit, MLX, model catalogs, and formatting logic themselves.
2. Support three integration surfaces: localhost HTTP, macOS XPC, and a CLI bridge.
3. Support streaming results from OpenType-managed recording first, then extend the same session model to client-provided audio files and audio chunks.
4. Keep the developer interface disabled by default, gated by user approval, local tokens, and explicitly registered apps.
5. Share one core service layer across all transports so HTTP, XPC, CLI, and the menu bar flow do not drift into separate implementations.

## Non-goals

- No remote or LAN-accessible API. All integration surfaces are local-only.
- No direct text insertion for external callers in the first version. The API returns text to the caller; the caller decides how to use it.
- No always-on LaunchAgent in the first version. CLI and XPC may launch OpenType, but HTTP is available only while OpenType is already running.
- No multi-session microphone recording in the first version. Only one active input session may record at a time.
- No full rewrite of `VoicePipeline`, model catalogs, or the menu bar UI path as part of the first implementation.

## Confirmed decisions

| Topic | Decision |
|---|---|
| Result ownership | OpenType returns text to the caller; it does not insert into the caller app. |
| Recording ownership | Support both OpenType-managed recording and caller-provided audio. First version prioritizes OpenType-managed recording. |
| Transports | Support HTTP, XPC, and CLI. |
| Streaming | Support streaming text events. Reserve caller streaming audio chunks for Phase 4. |
| Security default | Developer interface is off by default and must be enabled in Settings. |
| HTTP auth | Local bearer token required. |
| XPC/CLI auth | Local authorization plus explicit app registration. |
| App trust | Store registered app identity such as bundle id, team id, and code requirement where available. |
| Launch behavior | CLI and XPC can launch OpenType. HTTP works only when OpenType is already running. |
| Implementation direction | Build a shared core service first, then thin transport adapters. |

## Architecture

Add a new `Sources/Integration/` module area around a transport-neutral service:

```text
Sources/Integration/
+-- OpenTypeService.swift
+-- InputSessionCoordinator.swift
+-- InputSession.swift
+-- InputSessionEvent.swift
+-- InputSessionRequest.swift
+-- IntegrationAuth.swift
+-- IntegrationClientRegistry.swift
+-- IntegrationHTTPServer.swift
+-- IntegrationXPCService.swift
+-- IntegrationCLIBridge.swift
```

`OpenTypeService` is the stable boundary that all transports call. It owns session creation, authorization checks, event subscriptions, cancellation, and error normalization. It should not know whether a caller came from HTTP, XPC, or CLI.

`InputSessionCoordinator` owns the actual input workflow for external integrations. It reuses `AudioCaptureManager`, `SpeechEngine`, and `TextProcessor`, but does not call `TextInserter`. It emits events and final text only.

`VoicePipeline` remains the menu bar and hotkey coordinator. In the first implementation, it can keep its current behavior. After the first API release, it can be gradually moved onto `InputSessionCoordinator` for shared recording and processing behavior, but that is not required for the initial API.

## Core service API

The internal Swift-facing service should expose operations equivalent to:

```swift
func createSession(_ request: InputSessionRequest, client: IntegrationClient) async throws -> InputSession
func startRecording(sessionID: UUID) async throws
func stop(sessionID: UUID) async throws
func cancel(sessionID: UUID) async
func events(sessionID: UUID) -> AsyncStream<InputSessionEvent>

// Reserved for caller-provided audio.
func transcribeFile(sessionID: UUID, fileURL: URL) async throws
func appendAudio(sessionID: UUID, chunk: AudioChunk) async throws
func finishAudio(sessionID: UUID) async throws
```

The first version implements the OpenType-managed recording path:

1. Create a session.
2. Subscribe to events.
3. Start recording.
4. Receive partial transcript events while speaking when the selected engine supports streaming.
5. Stop recording.
6. Receive final transcript, optional processing events, final processed text, and completion.

## Event model

All transports share one event vocabulary. Events must be representable as JSON.

| Event | Meaning |
|---|---|
| `session.created` | Session exists and is ready for recording or audio input. |
| `recording.started` | OpenType began microphone capture. |
| `audio.received` | Reserved for caller-provided audio chunks or files. |
| `transcript.partial` | Streaming ASR partial text. |
| `transcript.final` | Final raw transcript. |
| `processing.started` | Smart formatting or command processing began. |
| `text.final` | Final text returned to the caller. |
| `session.completed` | Session finished successfully. |
| `session.cancelled` | Session was cancelled by the caller or OpenType. |
| `session.failed` | Session failed with a structured error. |

Example JSON events:

```json
{"type":"transcript.partial","session_id":"7C8C...","text":"today we are"}
{"type":"transcript.final","session_id":"7C8C...","text":"today we are designing an api"}
{"type":"text.final","session_id":"7C8C...","text":"Today we are designing an API."}
```

Event fields should include `session_id`, `sequence`, and `timestamp` so clients can order events safely.

## HTTP API

The HTTP server is local-only and listens on `127.0.0.1`. It is disabled unless the user enables the developer interface in Settings. Every request must include:

```text
Authorization: Bearer <local-token>
```

First-version endpoints:

```text
POST /v1/sessions
GET  /v1/sessions/{id}/events
POST /v1/sessions/{id}/recording/start
POST /v1/sessions/{id}/recording/stop
POST /v1/sessions/{id}/cancel
```

Reserved endpoints:

```text
POST /v1/sessions/{id}/audio/file
POST /v1/sessions/{id}/audio
POST /v1/sessions/{id}/audio/finish
```

Streaming output should use Server-Sent Events first because it is simple for scripts, browsers, Electron apps, and local tools. Phase 4 caller-provided streaming audio should use WebSocket or chunked HTTP upload while still reusing the same event stream.

## XPC API

XPC is the preferred native macOS integration surface. It can launch OpenType if OpenType is not running. XPC calls must be checked against the integration client registry.

The trust record should store:

- Bundle identifier.
- Team identifier when available.
- Code requirement when available.
- Display name.
- First approved date.
- Last used date.
- Allowed capabilities.

Unknown callers should trigger a user confirmation prompt in OpenType before a session is allowed. Denied callers receive `unauthorized_client`.

## CLI bridge

Ship a lightweight CLI bridge that does not load models. The CLI only talks to the running or launchable OpenType app through XPC or HTTP.

Example shape:

```text
opentype input --stream
opentype input --json
opentype transcribe-file ./voice.m4a --stream
opentype integrations status
```

Streaming CLI output should use JSON Lines:

```jsonl
{"type":"transcript.partial","session_id":"...","text":"let us"}
{"type":"transcript.final","session_id":"...","text":"let us design the api"}
{"type":"text.final","session_id":"...","text":"Let's design the API."}
```

The bundled CLI is trusted only when it is part of the signed OpenType bundle. If copied outside the bundle, it should be treated like any other caller and require registration.

## Settings and user control

Add an Integrations or Developer Interface section to Settings:

- Enable developer interface.
- Show HTTP local address and port.
- Copy HTTP token.
- Reset HTTP token.
- List registered apps.
- Show bundle id, team id, last used date, and allowed capabilities.
- Remove or revoke an app.

The developer interface must remain off by default. Enabling it should explain that local apps can request transcription and formatted text through OpenType.

## Authorization model

Authorization has two layers:

1. Developer interface must be enabled.
2. The caller must be authorized for its transport.

HTTP requires the bearer token. XPC and CLI require a registered local app identity, except for the bundled CLI path if it can be verified as part of the signed OpenType app.

All transports are local-only. The HTTP server must not bind to `0.0.0.0`.

## Error model

Errors should be stable machine-readable values with user-facing messages:

```json
{"error":"developer_interface_disabled","message":"Developer interface is disabled."}
{"error":"unauthorized_client","message":"This app is not allowed to use OpenType."}
{"error":"busy","message":"Another input session is active."}
{"error":"model_not_ready","message":"Speech model is not ready."}
{"error":"permission_denied","message":"Microphone permission is required."}
{"error":"session_not_found","message":"Input session was not found."}
{"error":"session_cancelled","message":"Input session was cancelled."}
```

The same error identifiers should be used in HTTP response bodies, XPC errors, CLI JSON output, and `session.failed` events.

## Concurrency and lifecycle

First version concurrency should be conservative:

- One active microphone recording session at a time.
- Additional start requests return `busy`.
- A session may be cancelled at any time.
- Completed, cancelled, and failed sessions are retained briefly for clients to fetch final state, then evicted.
- The HTTP server starts only when developer mode is enabled and OpenType is running.
- CLI and XPC may launch OpenType before making a request.

## Processing modes

Session requests should allow the caller to choose output behavior:

- `direct`: return cleaned transcript.
- `processed`: return smart formatted text.
- `command`: return command-mode result.

If no mode is provided, use the user's current OpenType setting. The first implementation can keep screen context disabled for external callers unless explicitly requested and permitted, because screen capture adds another privacy-sensitive capability.

## Phased implementation

### Phase 1: Service core

- Add session, event, request, response, and error types.
- Add developer-interface settings.
- Add integration client registry.
- Add single-session state machine.
- Add fake engines and unit tests for state transitions and event encoding.

### Phase 2: OpenType-managed recording streams

- Add `InputSessionCoordinator` for microphone recording sessions.
- Emit partial transcript, final transcript, processing, final text, completion, failure, and cancellation events.
- Add HTTP SSE support.
- Add CLI JSON Lines support.

### Phase 3: XPC and app registration

- Add XPC surface and auto-launch behavior.
- Add caller identity checks.
- Add first-use authorization prompt.
- Add Settings UI for registered apps.

### Phase 4: Caller-provided audio

- Add file transcription.
- Add chunked or streaming audio input.
- Reuse the same event model and session lifecycle.
- Add client examples for Swift, Node, and Python.

## Testing strategy

- Unit tests for session state transitions.
- Unit tests for authorization decisions.
- Unit tests for event JSON encoding and stable error identifiers.
- Fake speech engine tests for partial, final, processed, failed, cancelled, and busy event sequences.
- HTTP integration tests for disabled, unauthorized, busy, cancel, and event-stream behavior.
- CLI integration tests for JSON Lines output and error propagation.
- Manual validation for microphone permission, XPC code signature checks, first-use app authorization, and macOS TCC behavior.

## Open implementation notes

- Keep files under the project guideline of 300 lines where practical by splitting auth, events, server, and coordinator responsibilities.
- Prefer enum namespaces and structs for stateless helpers.
- Keep all UI-touching code on `@MainActor`.
- Avoid direct dependencies from transport adapters into `VoicePipeline`.
- Add localized strings for every user-facing Settings label, prompt, and error message shown in the app.
