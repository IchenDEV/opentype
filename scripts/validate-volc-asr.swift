#!/usr/bin/env swift

import AVFoundation
import Compression
import Foundation

enum ValidateError: LocalizedError {
    case missingConfig(String)
    case invalidArguments(String)
    case receiveTimeout
    case unexpectedMessage(String)
    case serverError(Int, String)
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .missingConfig(let key):
            return "Missing config: \(key)"
        case .invalidArguments(let message):
            return message
        case .receiveTimeout:
            return "Timed out waiting for server response"
        case .unexpectedMessage(let message):
            return "Unexpected message: \(message)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .audioConversionFailed:
            return "Failed to convert audio to 16kHz PCM"
        }
    }
}

enum Gzip {
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        guard let deflated = deflate(data) else { return nil }

        var result = Data(capacity: 10 + deflated.count + 8)
        result.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        result.append(deflated)
        var crc = crc32(data)
        withUnsafeBytes(of: &crc) { result.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count)
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        return result
    }

    static func decompress(_ data: Data) -> Data? {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else { return nil }

        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard data.count >= offset + 2 else { return nil }
            offset += 2 + Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }
        if flags & 0x08 != 0 { while offset < data.count, data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < data.count, data[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }

        guard offset < data.count - 8 else { return nil }
        return inflate(Data(data[offset..<(data.count - 8)]))
    }

    private static func deflate(_ data: Data) -> Data? {
        let dstSize = max(data.count + 1024, 65536)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(dst, dstSize, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return written > 0 ? Data(bytes: dst, count: written) : nil
    }

    private static func inflate(_ data: Data) -> Data? {
        var capacity = max(data.count * 8, 65536)
        while capacity <= 50_000_000 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            let written = data.withUnsafeBytes { src -> Int in
                guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dst, capacity, base, data.count, nil, COMPRESSION_ZLIB)
            }
            if written == 0 { dst.deallocate(); return nil }
            if written < capacity {
                let result = Data(bytes: dst, count: written)
                dst.deallocate()
                return result
            }
            dst.deallocate()
            capacity *= 2
        }
        return nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
}

struct Config {
    let appKey: String
    let accessKey: String
    let resourceId: String
    let language: String?
    let audioPath: String?
}

struct ParsedResponse {
    var text: String?
    var errorCode: Int?
    var errorMessage: String?
    var isFinal = false
}

let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel")!
let chunkSize = 6400
let timeoutSeconds: UInt64 = 30

func usage() {
    print("""
    Usage: swift scripts/validate-volc-asr.swift [--audio /path/to/file] [--language zh-CN]

    Defaults:
      - Reads volcAppKey / volcAccessKey / volcResourceId from defaults domain com.opentype.voiceinput
      - Generates a short test tone if --audio is not provided
    """)
}

func loadDefaultsValue(_ key: String) -> String? {
    UserDefaults.standard.persistentDomain(forName: "com.opentype.voiceinput")?[key] as? String
}

func parseConfig() throws -> Config {
    var audioPath: String?
    var language: String? = "zh-CN"
    var index = 1
    let args = CommandLine.arguments

    while index < args.count {
        switch args[index] {
        case "--audio":
            index += 1
            guard index < args.count else { throw ValidateError.invalidArguments("--audio requires a path") }
            audioPath = args[index]
        case "--language":
            index += 1
            guard index < args.count else { throw ValidateError.invalidArguments("--language requires a value") }
            language = args[index]
        case "--help", "-h":
            usage()
            exit(0)
        default:
            throw ValidateError.invalidArguments("Unknown argument: \(args[index])")
        }
        index += 1
    }

    guard let appKey = loadDefaultsValue("volcAppKey"), !appKey.isEmpty else {
        throw ValidateError.missingConfig("volcAppKey")
    }
    guard let accessKey = loadDefaultsValue("volcAccessKey"), !accessKey.isEmpty else {
        throw ValidateError.missingConfig("volcAccessKey")
    }
    let resourceId = loadDefaultsValue("volcResourceId").flatMap { $0.isEmpty ? nil : $0 } ?? "volc.bigasr.sauc.duration"

    return Config(appKey: appKey, accessKey: accessKey, resourceId: resourceId, language: language, audioPath: audioPath)
}

func generateTonePCM16(durationSeconds: Double = 1.0, frequency: Double = 440.0) -> Data {
    let sampleRate = 16_000.0
    let frameCount = Int(sampleRate * durationSeconds)
    var data = Data(capacity: frameCount * 2)

    for n in 0..<frameCount {
        let t = Double(n) / sampleRate
        let sample = sin(2 * Double.pi * frequency * t) * 0.2
        let intSample = Int16(max(-1, min(1, sample)) * Double(Int16.max))
        var littleEndian = intSample.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

func convertToPCM16k(url: URL) throws -> Data {
    let srcFile = try AVAudioFile(forReading: url)
    let srcFormat = srcFile.processingFormat

    guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
        throw ValidateError.audioConversionFailed
    }
    guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
        throw ValidateError.audioConversionFailed
    }

    let ratio = 16000.0 / srcFormat.sampleRate
    let estimatedFrames = AVAudioFrameCount(Double(srcFile.length) * ratio) + 100
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: estimatedFrames) else {
        throw ValidateError.audioConversionFailed
    }

    var conversionError: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        let frameCount: AVAudioFrameCount = 4096
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            outStatus.pointee = .endOfStream
            return nil
        }

        do {
            try srcFile.read(into: readBuffer)
            if readBuffer.frameLength == 0 {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return readBuffer
        } catch {
            outStatus.pointee = .endOfStream
            return nil
        }
    }

    converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
    if conversionError != nil { throw ValidateError.audioConversionFailed }
    guard let int16Data = outputBuffer.int16ChannelData else { throw ValidateError.audioConversionFailed }
    return Data(bytes: int16Data[0], count: Int(outputBuffer.frameLength) * 2)
}

func buildMessage(type: UInt8, flags: UInt8, serialization: UInt8, compression: UInt8 = 1, payload: Data) -> Data {
    let finalPayload = compression == 1 ? (Gzip.compress(payload) ?? payload) : payload
    var data = Data(capacity: 8 + finalPayload.count)
    data.append(0x11)
    data.append((type << 4) | (flags & 0x0F))
    data.append((serialization << 4) | (compression == 1 ? 1 : 0))
    data.append(0x00)
    let size = UInt32(finalPayload.count)
    data.append(UInt8((size >> 24) & 0xFF))
    data.append(UInt8((size >> 16) & 0xFF))
    data.append(UInt8((size >> 8) & 0xFF))
    data.append(UInt8(size & 0xFF))
    data.append(finalPayload)
    return data
}

func parseResponse(_ data: Data) throws -> ParsedResponse {
    guard data.count >= 8 else { throw ValidateError.unexpectedMessage("frame too short") }
    let msgType = (data[1] >> 4) & 0x0F
    let flags = data[1] & 0x0F
    let headerSize = Int(data[0] & 0x0F) * 4
    var offset = headerSize

    if (flags & 0x01) != 0 || (flags & 0x03) == 0x03 {
        offset += 4
    }
    guard data.count >= offset + 4 else { throw ValidateError.unexpectedMessage("missing payload size") }

    let payloadSize = Int(UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3]))
    offset += 4
    guard data.count >= offset + payloadSize else { throw ValidateError.unexpectedMessage("payload truncated") }

    if msgType == 0x0F {
        let payload = Data(data[offset..<(offset + payloadSize)])
        if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            let code = json["code"] as? Int ?? -1
            let message = json["message"] as? String ?? "Unknown"
            return ParsedResponse(text: nil, errorCode: code, errorMessage: message, isFinal: true)
        }
        return ParsedResponse(text: nil, errorCode: -1, errorMessage: "Unknown server error", isFinal: true)
    }

    let payload = Data(data[offset..<(offset + payloadSize)])
    let decoded = (data[2] & 0x0F) == 0x01 ? (Gzip.decompress(payload) ?? payload) : payload
    guard let json = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
        throw ValidateError.unexpectedMessage("non-JSON server payload")
    }

    if let code = json["code"] as? Int, code != 0 {
        let message = json["message"] as? String ?? "Server error \(code)"
        return ParsedResponse(text: nil, errorCode: code, errorMessage: message, isFinal: true)
    }

    let result = json["result"] as? [String: Any]
    return ParsedResponse(text: result?["text"] as? String, errorCode: nil, errorMessage: nil, isFinal: (flags & 0x02) != 0)
}

func receiveWithTimeout(task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
    try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
        group.addTask { try await task.receive() }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            throw ValidateError.receiveTimeout
        }
        let message = try await group.next()!
        group.cancelAll()
        return message
    }
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    defer { semaphore.signal() }

    do {
        let config = try parseConfig()
        let audio = try config.audioPath.map { try convertToPCM16k(url: URL(fileURLWithPath: $0)) } ?? generateTonePCM16()

        print("Using resourceId: \(config.resourceId)")
        print("Audio source: \(config.audioPath ?? "generated test tone")")
        print("PCM bytes: \(audio.count)")

        var request = URLRequest(url: endpoint)
        request.setValue(config.appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue("swift-validate-\(UUID().uuidString)", forHTTPHeaderField: "X-Api-Connect-Id")

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        task.resume()

        let payload: [String: Any] = [
            "user": ["uid": "opentype_validate_script"],
            "audio": [
                "format": "pcm",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "codec": "raw",
                "language": config.language as Any
            ].compactMapValues { $0 },
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": false
            ]
        ]

        let json = try JSONSerialization.data(withJSONObject: payload)
        try await task.send(.data(buildMessage(type: 0x01, flags: 0x00, serialization: 0x01, payload: json)))

        if case .data(let handshakeData) = try await receiveWithTimeout(task: task) {
            let handshake = try parseResponse(handshakeData)
            if let code = handshake.errorCode {
                throw ValidateError.serverError(code, handshake.errorMessage ?? "Unknown")
            }
            print("Handshake response received")
        } else {
            throw ValidateError.unexpectedMessage("handshake response was not binary")
        }

        var lastText = ""
        let totalChunks = (audio.count + chunkSize - 1) / chunkSize
        for index in 0..<totalChunks {
            let start = index * chunkSize
            let end = min(start + chunkSize, audio.count)
            let isLast = index == totalChunks - 1
            let chunk = Data(audio[start..<end])
            let frame = buildMessage(type: 0x02, flags: isLast ? 0x02 : 0x00, serialization: 0x00, payload: chunk)
            try await task.send(.data(frame))

            if case .data(let responseData) = try await receiveWithTimeout(task: task) {
                let response = try parseResponse(responseData)
                if let code = response.errorCode {
                    throw ValidateError.serverError(code, response.errorMessage ?? "Unknown")
                }
                if let text = response.text, !text.isEmpty {
                    lastText = text
                }
                print("Chunk \(index + 1)/\(totalChunks) ok" + (response.isFinal ? " (final)" : ""))
            } else {
                throw ValidateError.unexpectedMessage("audio response was not binary")
            }
        }

        print(lastText.isEmpty ? "Validation succeeded; server returned no text for this audio." : "Validation succeeded; text: \(lastText)")
        task.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()
    } catch {
        fputs("Validation failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

semaphore.wait()
