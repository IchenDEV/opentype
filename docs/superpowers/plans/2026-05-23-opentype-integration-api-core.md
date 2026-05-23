# OpenType Integration API Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first testable slice of the OpenType integration API: transport-neutral session models, event/error encoding, developer-interface settings, local client authorization, and a single-session service state machine.

**Architecture:** This plan implements the shared core beneath HTTP, XPC, and CLI without adding those transports yet. New files live under `Sources/Integration/`; `AppSettings` persists the developer-interface switch and HTTP token; tests exercise JSON contracts, authorization, registry persistence, and session lifecycle. `VoicePipeline` is left untouched in this slice.

**Tech Stack:** Swift 6 package, Foundation, Combine-backed `AppSettings`, XCTest, `UserDefaults`, `JSONEncoder`/`JSONDecoder`.

---

## Scope

This plan implements Phase 1 of `docs/superpowers/specs/2026-05-23-opentype-integration-api-design.md`.

Included:

- Integration request, session, event, error, client, and authorization types.
- Stable JSON encoding for events and errors.
- Developer-interface settings on `AppSettings`.
- Local integration client registry using `UserDefaults`.
- `OpenTypeService` with one active session at a time.
- Unit tests for all of the above.

Deferred to later plans:

- HTTP server and SSE.
- CLI bridge and JSON Lines.
- XPC service and code-signature checks.
- Real microphone recording through `InputSessionCoordinator`.
- Caller-provided audio file/chunk input.
- Settings UI for registered-app management.

## File Structure

- Create `Sources/Integration/InputSessionModels.swift`
  - Owns `InputSessionRequest`, `InputSession`, `InputSessionState`, `InputSessionEvent`, and small encoding helpers.
- Create `Sources/Integration/IntegrationError.swift`
  - Owns stable machine-readable integration errors and JSON payloads.
- Create `Sources/Integration/IntegrationClient.swift`
  - Owns caller identity and capability models.
- Create `Sources/Integration/IntegrationClientRegistry.swift`
  - Owns persistence and lookup for approved integration clients.
- Create `Sources/Integration/OpenTypeService.swift`
  - Owns authorization, session lifecycle, event buffering, and single-active-session rules.
- Modify `Sources/Config/AppSettings.swift`
  - Add persisted developer-interface settings and token helper.
- Modify `Sources/Resources/en.lproj/Localizable.strings`
  - Add English labels/messages for developer-interface settings.
- Modify `Sources/Resources/zh-Hans.lproj/Localizable.strings`
  - Add Simplified Chinese labels/messages for the same keys.
- Create `Tests/OpenTypeTests/IntegrationModelTests.swift`
  - Tests event/error JSON contracts.
- Create `Tests/OpenTypeTests/IntegrationAuthTests.swift`
  - Tests developer-interface gating and client authorization.
- Create `Tests/OpenTypeTests/OpenTypeServiceTests.swift`
  - Tests session lifecycle and busy/cancel behavior.
- Modify `Tests/OpenTypeTests/ConfigurationTests.swift`
  - Tests developer-interface defaults.

## Task 1: Event, Request, Session, and Error Models

**Files:**
- Create: `Sources/Integration/InputSessionModels.swift`
- Create: `Sources/Integration/IntegrationError.swift`
- Test: `Tests/OpenTypeTests/IntegrationModelTests.swift`

- [ ] **Step 1: Write failing JSON contract tests**

Create `Tests/OpenTypeTests/IntegrationModelTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenType

final class IntegrationModelTests: XCTestCase {
    func testInputSessionEventEncodesStableJSONKeys() throws {
        let event = InputSessionEvent(
            type: .transcriptPartial,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sequence: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            text: "hello",
            error: nil
        )

        let data = try JSONEncoder.integration.encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "transcript.partial")
        XCTAssertEqual(object["session_id"] as? String, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(object["sequence"] as? Int, 2)
        XCTAssertEqual(object["text"] as? String, "hello")
        XCTAssertNotNil(object["timestamp"])
        XCTAssertNil(object["error"])
    }

    func testIntegrationErrorPayloadUsesStableIdentifier() throws {
        let payload = IntegrationError.developerInterfaceDisabled.payload

        XCTAssertEqual(payload.error, "developer_interface_disabled")
        XCTAssertEqual(payload.message, "Developer interface is disabled.")

        let data = try JSONEncoder.integration.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["error"] as? String, "developer_interface_disabled")
        XCTAssertEqual(object["message"] as? String, "Developer interface is disabled.")
    }

    func testInputSessionRequestDefaultsToCurrentSettingsWhenModeIsMissing() {
        let request = InputSessionRequest(mode: nil, language: nil, useScreenContext: nil)

        XCTAssertNil(request.mode)
        XCTAssertNil(request.language)
        XCTAssertNil(request.useScreenContext)
    }

    func testEventTypeRawValuesRemainStable() {
        XCTAssertEqual(InputSessionEvent.EventType.sessionCreated.rawValue, "session.created")
        XCTAssertEqual(InputSessionEvent.EventType.recordingStarted.rawValue, "recording.started")
        XCTAssertEqual(InputSessionEvent.EventType.transcriptPartial.rawValue, "transcript.partial")
        XCTAssertEqual(InputSessionEvent.EventType.transcriptFinal.rawValue, "transcript.final")
        XCTAssertEqual(InputSessionEvent.EventType.processingStarted.rawValue, "processing.started")
        XCTAssertEqual(InputSessionEvent.EventType.textFinal.rawValue, "text.final")
        XCTAssertEqual(InputSessionEvent.EventType.sessionCompleted.rawValue, "session.completed")
        XCTAssertEqual(InputSessionEvent.EventType.sessionCancelled.rawValue, "session.cancelled")
        XCTAssertEqual(InputSessionEvent.EventType.sessionFailed.rawValue, "session.failed")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter IntegrationModelTests
```

Expected: FAIL because `InputSessionEvent`, `InputSessionRequest`, `IntegrationError`, and `JSONEncoder.integration` do not exist.

- [ ] **Step 3: Add model implementation**

Create `Sources/Integration/InputSessionModels.swift`:

```swift
import Foundation

struct InputSessionRequest: Codable, Equatable {
    var mode: OutputMode?
    var language: InputLanguage?
    var useScreenContext: Bool?
}

struct InputSession: Codable, Equatable, Identifiable {
    let id: UUID
    var request: InputSessionRequest
    var state: InputSessionState
    var createdAt: Date
    var updatedAt: Date
}

enum InputSessionState: String, Codable, Equatable {
    case created
    case recording
    case processing
    case completed
    case cancelled
    case failed

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .created, .recording, .processing:
            return false
        }
    }
}

struct InputSessionEvent: Codable, Equatable {
    enum EventType: String, Codable {
        case sessionCreated = "session.created"
        case recordingStarted = "recording.started"
        case audioReceived = "audio.received"
        case transcriptPartial = "transcript.partial"
        case transcriptFinal = "transcript.final"
        case processingStarted = "processing.started"
        case textFinal = "text.final"
        case sessionCompleted = "session.completed"
        case sessionCancelled = "session.cancelled"
        case sessionFailed = "session.failed"
    }

    let type: EventType
    let sessionID: UUID
    let sequence: Int
    let timestamp: Date
    let text: String?
    let error: IntegrationError.Payload?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case sequence
        case timestamp
        case text
        case error
    }
}

extension JSONEncoder {
    static var integration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var integration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

Create `Sources/Integration/IntegrationError.swift`:

```swift
import Foundation

enum IntegrationError: Error, Equatable {
    struct Payload: Codable, Equatable {
        let error: String
        let message: String
    }

    case developerInterfaceDisabled
    case unauthorizedClient
    case busy
    case modelNotReady
    case permissionDenied
    case sessionNotFound
    case sessionCancelled
    case invalidSessionState

    var payload: Payload {
        switch self {
        case .developerInterfaceDisabled:
            return Payload(error: "developer_interface_disabled", message: "Developer interface is disabled.")
        case .unauthorizedClient:
            return Payload(error: "unauthorized_client", message: "This app is not allowed to use OpenType.")
        case .busy:
            return Payload(error: "busy", message: "Another input session is active.")
        case .modelNotReady:
            return Payload(error: "model_not_ready", message: "Speech model is not ready.")
        case .permissionDenied:
            return Payload(error: "permission_denied", message: "Microphone permission is required.")
        case .sessionNotFound:
            return Payload(error: "session_not_found", message: "Input session was not found.")
        case .sessionCancelled:
            return Payload(error: "session_cancelled", message: "Input session was cancelled.")
        case .invalidSessionState:
            return Payload(error: "invalid_session_state", message: "Input session is not in a valid state for this operation.")
        }
    }
}
```

- [ ] **Step 4: Run model tests**

Run:

```bash
swift test --filter IntegrationModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Integration/InputSessionModels.swift Sources/Integration/IntegrationError.swift Tests/OpenTypeTests/IntegrationModelTests.swift
git commit -m "Add integration session model contracts"
```

## Task 2: Developer Interface Settings and Token

**Files:**
- Modify: `Sources/Config/AppSettings.swift`
- Modify: `Sources/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/OpenTypeTests/ConfigurationTests.swift`

- [ ] **Step 1: Write failing configuration tests**

Append these tests inside `ConfigurationTests`:

```swift
func testDeveloperInterfaceDefaultsOff() {
    XCTAssertFalse(AppSettings.shared.developerInterfaceEnabled)
}

func testDeveloperHTTPTokenCanBeReset() {
    let settings = AppSettings.shared
    let original = settings.developerHTTPToken

    settings.resetDeveloperHTTPToken()
    let reset = settings.developerHTTPToken

    XCTAssertFalse(reset.isEmpty)
    XCTAssertNotEqual(reset, original)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ConfigurationTests/testDeveloper
```

Expected: FAIL because the developer-interface settings do not exist.

- [ ] **Step 3: Add persisted settings**

Modify `Sources/Config/AppSettings.swift`:

1. Add properties near other `@Published` settings:

```swift
@Published var developerInterfaceEnabled: Bool
@Published var developerHTTPPort: Int
@Published var developerHTTPToken: String
```

2. Add keys in the private `Key` enum:

```swift
case developerInterfaceEnabled, developerHTTPPort, developerHTTPToken
```

3. Initialize after existing boolean/interface settings:

```swift
developerInterfaceEnabled = ud.bool(forKey: Key.developerInterfaceEnabled.rawValue)
developerHTTPPort = (ud.integer(forKey: Key.developerHTTPPort.rawValue)).nonZeroInt ?? 38765
developerHTTPToken = ud.string(forKey: Key.developerHTTPToken.rawValue) ?? Self.generateDeveloperHTTPToken()
if ud.string(forKey: Key.developerHTTPToken.rawValue) == nil {
    ud.set(developerHTTPToken, forKey: Key.developerHTTPToken.rawValue)
}
```

4. Add persistence sinks in `setupPersistence()`:

```swift
$developerInterfaceEnabled.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerInterfaceEnabled.rawValue) }.store(in: &cancellables)
$developerHTTPPort.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerHTTPPort.rawValue) }.store(in: &cancellables)
$developerHTTPToken.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.developerHTTPToken.rawValue) }.store(in: &cancellables)
```

5. Add helper methods before `var zh`:

```swift
func resetDeveloperHTTPToken() {
    developerHTTPToken = Self.generateDeveloperHTTPToken()
}

private static func generateDeveloperHTTPToken() -> String {
    let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
    return Data(bytes).base64EncodedString()
}
```

- [ ] **Step 4: Add localization keys**

Append to both localization files under Settings:

English:

```text
"settings.integrations" = "Integrations";
"settings.developer_interface" = "Developer interface";
"settings.developer_interface_help" = "Allow approved local apps to request transcription and formatted text through OpenType.";
"settings.developer_http_address" = "HTTP address";
"settings.developer_http_token" = "HTTP token";
"settings.developer_reset_token" = "Reset Token";
"settings.registered_apps" = "Registered Apps";
```

Simplified Chinese:

```text
"settings.integrations" = "集成";
"settings.developer_interface" = "开发者接口";
"settings.developer_interface_help" = "允许已授权的本机应用通过 OpenType 请求语音识别和文本整理。";
"settings.developer_http_address" = "HTTP 地址";
"settings.developer_http_token" = "HTTP Token";
"settings.developer_reset_token" = "重置 Token";
"settings.registered_apps" = "已授权应用";
```

- [ ] **Step 5: Run configuration tests**

Run:

```bash
swift test --filter ConfigurationTests/testDeveloper
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Config/AppSettings.swift Sources/Resources/en.lproj/Localizable.strings Sources/Resources/zh-Hans.lproj/Localizable.strings Tests/OpenTypeTests/ConfigurationTests.swift
git commit -m "Add developer interface settings"
```

## Task 3: Integration Client Registry

**Files:**
- Create: `Sources/Integration/IntegrationClient.swift`
- Create: `Sources/Integration/IntegrationClientRegistry.swift`
- Test: `Tests/OpenTypeTests/IntegrationAuthTests.swift`

- [ ] **Step 1: Write failing registry tests**

Create `Tests/OpenTypeTests/IntegrationAuthTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenType

final class IntegrationAuthTests: XCTestCase {
    private func registry() -> IntegrationClientRegistry {
        let suiteName = "IntegrationAuthTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return IntegrationClientRegistry(defaults: defaults)
    }

    func testRegistryStartsEmpty() {
        XCTAssertTrue(registry().approvedClients().isEmpty)
    }

    func testApprovingClientPersistsIdentity() throws {
        let registry = registry()
        let client = IntegrationClient(
            id: "com.example.Writer:TEAMID",
            displayName: "Writer",
            bundleIdentifier: "com.example.Writer",
            teamIdentifier: "TEAMID",
            codeRequirement: "anchor apple generic",
            transport: .xpc,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil
        )

        registry.approve(client)

        let saved = try XCTUnwrap(registry.client(id: "com.example.Writer:TEAMID"))
        XCTAssertEqual(saved.bundleIdentifier, "com.example.Writer")
        XCTAssertEqual(saved.teamIdentifier, "TEAMID")
        XCTAssertTrue(saved.capabilities.contains(.record))
    }

    func testAuthorizationRequiresApprovedClientAndCapability() {
        let registry = registry()
        let client = IntegrationClient.localHTTP(tokenID: "token")

        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .record))

        registry.approve(client)

        XCTAssertTrue(registry.isAuthorized(clientID: client.id, capability: .record))
        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .manageClients))
    }

    func testRevokingClientRemovesAccess() {
        let registry = registry()
        let client = IntegrationClient.localHTTP(tokenID: "token")
        registry.approve(client)

        registry.revoke(clientID: client.id)

        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .record))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter IntegrationAuthTests
```

Expected: FAIL because registry and client types do not exist.

- [ ] **Step 3: Add client models**

Create `Sources/Integration/IntegrationClient.swift`:

```swift
import Foundation

struct IntegrationClient: Codable, Equatable, Identifiable {
    enum Transport: String, Codable, Equatable {
        case http
        case xpc
        case cli
    }

    enum Capability: String, Codable, Equatable, Hashable {
        case record
        case streamEvents
        case provideAudio
        case manageClients
    }

    let id: String
    var displayName: String
    var bundleIdentifier: String?
    var teamIdentifier: String?
    var codeRequirement: String?
    var transport: Transport
    var capabilities: Set<Capability>
    var firstApprovedAt: Date
    var lastUsedAt: Date?

    static func localHTTP(tokenID: String) -> IntegrationClient {
        IntegrationClient(
            id: "http:\(tokenID)",
            displayName: "Local HTTP",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: .http,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(),
            lastUsedAt: nil
        )
    }
}
```

- [ ] **Step 4: Add registry implementation**

Create `Sources/Integration/IntegrationClientRegistry.swift`:

```swift
import Foundation

final class IntegrationClientRegistry {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "integrationApprovedClients") {
        self.defaults = defaults
        self.key = key
    }

    func approvedClients() -> [IntegrationClient] {
        load().sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func client(id: String) -> IntegrationClient? {
        load().first { $0.id == id }
    }

    func approve(_ client: IntegrationClient) {
        var clients = load().filter { $0.id != client.id }
        clients.append(client)
        save(clients)
    }

    func revoke(clientID: String) {
        save(load().filter { $0.id != clientID })
    }

    func markUsed(clientID: String, at date: Date = Date()) {
        var clients = load()
        guard let index = clients.firstIndex(where: { $0.id == clientID }) else { return }
        clients[index].lastUsedAt = date
        save(clients)
    }

    func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool {
        guard let client = client(id: clientID) else { return false }
        return client.capabilities.contains(capability)
    }

    private func load() -> [IntegrationClient] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.integration.decode([IntegrationClient].self, from: data)) ?? []
    }

    private func save(_ clients: [IntegrationClient]) {
        guard let data = try? JSONEncoder.integration.encode(clients) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 5: Run registry tests**

Run:

```bash
swift test --filter IntegrationAuthTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Integration/IntegrationClient.swift Sources/Integration/IntegrationClientRegistry.swift Tests/OpenTypeTests/IntegrationAuthTests.swift
git commit -m "Add integration client registry"
```

## Task 4: OpenTypeService State Machine

**Files:**
- Create: `Sources/Integration/OpenTypeService.swift`
- Test: `Tests/OpenTypeTests/OpenTypeServiceTests.swift`

- [ ] **Step 1: Write failing service tests**

Create `Tests/OpenTypeTests/OpenTypeServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenType

@MainActor
final class OpenTypeServiceTests: XCTestCase {
    private func service(enabled: Bool = true) -> OpenTypeService {
        let registry = IntegrationClientRegistry(defaults: UserDefaults(suiteName: "OpenTypeServiceTests-\(UUID().uuidString)")!)
        let settings = IntegrationServiceSettings(
            developerInterfaceEnabled: enabled,
            httpToken: "token"
        )
        let client = IntegrationClient.localHTTP(tokenID: "token")
        registry.approve(client)
        return OpenTypeService(settings: settings, registry: registry)
    }

    func testCreateSessionFailsWhenDeveloperInterfaceDisabled() async {
        do {
            _ = try await service(enabled: false).createSession(.init(mode: .direct, language: .english, useScreenContext: false), clientID: "http:token")
            XCTFail("Expected developerInterfaceDisabled")
        } catch let error as IntegrationError {
            XCTAssertEqual(error, .developerInterfaceDisabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateSessionEmitsCreatedEvent() async throws {
        let service = service()
        let session = try await service.createSession(.init(mode: .direct, language: .english, useScreenContext: false), clientID: "http:token")
        let events = service.snapshotEvents(sessionID: session.id)

        XCTAssertEqual(session.state, .created)
        XCTAssertEqual(events.map(\.type), [.sessionCreated])
        XCTAssertEqual(events.first?.sequence, 1)
    }

    func testOnlyOneActiveSessionCanRecord() async throws {
        let service = service()
        let first = try await service.createSession(.init(mode: .direct, language: .english, useScreenContext: false), clientID: "http:token")
        try await service.startRecording(sessionID: first.id)

        do {
            _ = try await service.createSession(.init(mode: .direct, language: .english, useScreenContext: false), clientID: "http:token")
            XCTFail("Expected busy")
        } catch let error as IntegrationError {
            XCTAssertEqual(error, .busy)
        }
    }

    func testCancelSessionTransitionsToTerminalState() async throws {
        let service = service()
        let session = try await service.createSession(.init(mode: .direct, language: .english, useScreenContext: false), clientID: "http:token")

        await service.cancel(sessionID: session.id)

        let events = service.snapshotEvents(sessionID: session.id)
        XCTAssertEqual(events.last?.type, .sessionCancelled)
        XCTAssertEqual(service.session(session.id)?.state, .cancelled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter OpenTypeServiceTests
```

Expected: FAIL because `OpenTypeService` and `IntegrationServiceSettings` do not exist.

- [ ] **Step 3: Add minimal service implementation**

Create `Sources/Integration/OpenTypeService.swift`:

```swift
import Foundation

struct IntegrationServiceSettings {
    var developerInterfaceEnabled: Bool
    var httpToken: String

    @MainActor
    static var live: IntegrationServiceSettings {
        IntegrationServiceSettings(
            developerInterfaceEnabled: AppSettings.shared.developerInterfaceEnabled,
            httpToken: AppSettings.shared.developerHTTPToken
        )
    }
}

@MainActor
final class OpenTypeService {
    private var sessions: [UUID: InputSession] = [:]
    private var eventsBySession: [UUID: [InputSessionEvent]] = [:]
    private var nextSequenceBySession: [UUID: Int] = [:]
    private let settings: IntegrationServiceSettings
    private let registry: IntegrationClientRegistry

    init(settings: IntegrationServiceSettings = .live, registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.settings = settings
        self.registry = registry
    }

    func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession {
        try authorize(clientID: clientID, capability: .record)
        guard !hasActiveSession else { throw IntegrationError.busy }

        let now = Date()
        let session = InputSession(
            id: UUID(),
            request: request,
            state: .created,
            createdAt: now,
            updatedAt: now
        )
        sessions[session.id] = session
        append(.sessionCreated, sessionID: session.id)
        registry.markUsed(clientID: clientID)
        return session
    }

    func startRecording(sessionID: UUID) async throws {
        guard var session = sessions[sessionID] else { throw IntegrationError.sessionNotFound }
        guard session.state == .created else { throw IntegrationError.invalidSessionState }
        guard !hasRecordingSession(excluding: sessionID) else { throw IntegrationError.busy }

        session.state = .recording
        session.updatedAt = Date()
        sessions[sessionID] = session
        append(.recordingStarted, sessionID: sessionID)
    }

    func cancel(sessionID: UUID) async {
        guard var session = sessions[sessionID], !session.state.isTerminal else { return }
        session.state = .cancelled
        session.updatedAt = Date()
        sessions[sessionID] = session
        append(.sessionCancelled, sessionID: sessionID)
    }

    func session(_ id: UUID) -> InputSession? {
        sessions[id]
    }

    func snapshotEvents(sessionID: UUID) -> [InputSessionEvent] {
        eventsBySession[sessionID] ?? []
    }

    private func authorize(clientID: String, capability: IntegrationClient.Capability) throws {
        guard settings.developerInterfaceEnabled else { throw IntegrationError.developerInterfaceDisabled }
        guard registry.isAuthorized(clientID: clientID, capability: capability) else {
            throw IntegrationError.unauthorizedClient
        }
    }

    private var hasActiveSession: Bool {
        sessions.values.contains { !$0.state.isTerminal }
    }

    private func hasRecordingSession(excluding sessionID: UUID) -> Bool {
        sessions.values.contains { $0.id != sessionID && $0.state == .recording }
    }

    private func append(_ type: InputSessionEvent.EventType, sessionID: UUID, text: String? = nil, error: IntegrationError? = nil) {
        let sequence = nextSequenceBySession[sessionID, default: 1]
        nextSequenceBySession[sessionID] = sequence + 1
        let event = InputSessionEvent(
            type: type,
            sessionID: sessionID,
            sequence: sequence,
            timestamp: Date(),
            text: text,
            error: error?.payload
        )
        eventsBySession[sessionID, default: []].append(event)
    }
}
```

- [ ] **Step 4: Run service tests**

Run:

```bash
swift test --filter OpenTypeServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Integration/OpenTypeService.swift Tests/OpenTypeTests/OpenTypeServiceTests.swift
git commit -m "Add integration service state machine"
```

## Task 5: Integrations Settings Tab Skeleton

**Files:**
- Create: `Sources/UI/IntegrationsSettingsView.swift`
- Modify: `Sources/UI/SettingsView.swift`

- [ ] **Step 1: Add the settings view**

Create `Sources/UI/IntegrationsSettingsView.swift`:

```swift
import SwiftUI

struct IntegrationsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(L("settings.developer_interface")) {
                Toggle(isOn: $settings.developerInterfaceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.developer_interface"))
                        Text(L("settings.developer_interface_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("HTTP") {
                LabeledContent(L("settings.developer_http_address")) {
                    Text("127.0.0.1:\(settings.developerHTTPPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent(L("settings.developer_http_token")) {
                    Text(settings.developerHTTPToken)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button(L("settings.developer_reset_token")) {
                    settings.resetDeveloperHTTPToken()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
```

- [ ] **Step 2: Add the tab**

Modify `Sources/UI/SettingsView.swift` inside `TabView` after `HistoryStatsView()`:

```swift
IntegrationsSettingsView()
    .tabItem { Label(L("settings.integrations"), systemImage: "point.3.connected.trianglepath.dotted") }
```

- [ ] **Step 3: Build to verify the UI compiles**

Run:

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/IntegrationsSettingsView.swift Sources/UI/SettingsView.swift
git commit -m "Add integrations settings tab"
```

## Task 6: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --filter IntegrationModelTests
swift test --filter IntegrationAuthTests
swift test --filter OpenTypeServiceTests
swift test --filter ConfigurationTests/testDeveloper
```

Expected: all PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests PASS.

- [ ] **Step 3: Run build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Check git status**

Run:

```bash
git status --short --branch
```

Expected: current branch contains only committed implementation changes, with no unexpected untracked files.

## Self-Review

- Spec coverage: This plan covers service core, event/error/request models, developer settings, local client registry, single-session state machine, and tests. It intentionally defers HTTP, CLI, XPC, real recording, and caller-provided audio to later plans because those are separate testable subsystems.
- Placeholder scan: No steps use placeholder terms or require unstated implementation details.
- Type consistency: `InputSessionRequest`, `InputSessionEvent`, `IntegrationError`, `IntegrationClient`, `IntegrationClientRegistry`, `IntegrationServiceSettings`, and `OpenTypeService` names are used consistently across tests and implementation steps.
