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
