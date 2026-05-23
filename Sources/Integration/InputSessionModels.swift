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
