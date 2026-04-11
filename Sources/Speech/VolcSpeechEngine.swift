import Foundation
import AVFoundation
import Network

final class VolcSpeechEngine: SpeechEngine {
    private let appKey: String
    private let accessKey: String
    private let resourceId: String

    private(set) var isReady: Bool

    private static let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    private static let host     = "openspeech.bytedance.com"
    private static let path     = "/api/v3/sauc/bigmodel"
    private static let chunkSize = 6400 // ~200ms at 16kHz 16-bit mono
    private static let timeoutSeconds: UInt64 = 30

    init(appKey: String, accessKey: String, resourceId: String) {
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
        self.isReady = !appKey.isEmpty && !accessKey.isEmpty && !resourceId.isEmpty
    }

    func startListening() {}

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard isReady else { throw VolcASRError.notConfigured }
        guard let url = audioURL else { throw VolcASRError.noAudioFile }

        Log.info("[VolcASR] connecting: endpoint=\(Self.endpoint) resourceId=\(resourceId) appKey=\(appKey.prefix(4))***")

        let t0 = CFAbsoluteTimeGetCurrent()
        let pcmData = try convertToPCM16k(url: url)
        guard !pcmData.isEmpty else { return "" }
        Log.info("[VolcASR] audio converted: \(pcmData.count) bytes PCM 16kHz")

        let connectId = UUID().uuidString
        let conn = try await openConnection(connectId: connectId)
        defer { conn.cancel() }

        let volcLang = volcLanguage(from: language)
        Log.info("[VolcASR] sending full client request, language=\(volcLang ?? "auto")")
        do {
            try await sendFullClientRequest(conn: conn, language: volcLang)
        } catch {
            Log.error("[VolcASR] send full client request failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }

        Log.info("[VolcASR] waiting for handshake response...")
        do {
            if let handshake = try await receiveResponse(conn: conn), let code = handshake.errorCode {
                Log.error("[VolcASR] handshake error: code=\(code) message=\(handshake.errorMessage ?? "nil")")
                throw VolcASRError.serverError(code: code, message: handshake.errorMessage ?? "Unknown")
            }
        } catch let error as VolcASRError {
            throw error
        } catch {
            Log.error("[VolcASR] handshake failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }
        Log.info("[VolcASR] handshake ok, streaming audio...")

        let text = try await streamAudioAndCollect(conn: conn, pcmData: pcmData)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[VolcASR] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    // MARK: - NWConnection (forces HTTP/1.1 via ALPN, avoiding HTTP/2 WebSocket rejection)

    private func openConnection(connectId: String) async throws -> NWConnection {
        // Force http/1.1 in ALPN — Volcengine BigModel does not support RFC 8441
        // (WebSocket over HTTP/2). URLSession.shared offers h2 in ALPN and the server
        // picks it, causing NSURLErrorBadServerResponse. NWConnection lets us restrict ALPN.
        let tlsOpts = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(
            tlsOpts.securityProtocolOptions, "http/1.1"
        )

        // skipHandshake = true: we send the HTTP/1.1 upgrade manually so we can include
        // custom auth headers that NWProtocolWebSocket.Options doesn't expose.
        let wsOpts = NWProtocolWebSocket.Options()
        wsOpts.skipHandshake = true
        wsOpts.autoReplyPing = true
        wsOpts.maximumMessageSize = 10 * 1024 * 1024

        let params = NWParameters(tls: tlsOpts)
        params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)

        let conn = NWConnection(host: NWEndpoint.Host(Self.host), port: 443, using: params)

        // Wait for connection ready
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    conn.stateUpdateHandler = { (state: NWConnection.State) in
                        switch state {
                        case .ready:
                            conn.stateUpdateHandler = nil
                            cont.resume()
                        case .failed(let err):
                            conn.stateUpdateHandler = nil
                            cont.resume(throwing: err)
                        case .cancelled:
                            conn.stateUpdateHandler = nil
                            cont.resume(throwing: VolcASRError.handshakeRejected)
                        default:
                            break
                        }
                    }
                    conn.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                conn.cancel()
                throw VolcASRError.timeout
            }
            try await group.next()
            group.cancelAll()
        }

        // Manual HTTP/1.1 WebSocket upgrade
        let wsKey = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let upgradeReq =
            "GET \(Self.path) HTTP/1.1\r\n" +
            "Host: \(Self.host)\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: \(wsKey)\r\n" +
            "Sec-WebSocket-Version: 13\r\n" +
            "X-Api-App-Key: \(appKey)\r\n" +
            "X-Api-Access-Key: \(accessKey)\r\n" +
            "X-Api-Resource-Id: \(resourceId)\r\n" +
            "X-Api-Connect-Id: \(connectId)\r\n" +
            "\r\n"

        try await nwSend(conn: conn, data: upgradeReq.data(using: .utf8)!)

        // Read HTTP 101 response
        let respData = try await nwReceiveRaw(conn: conn, maxBytes: 4096)
        let respStr  = String(data: respData, encoding: .utf8) ?? ""
        Log.info("[VolcASR] upgrade response: \(respStr.prefix(120))")
        guard respStr.contains("101") else {
            Log.error("[VolcASR] WebSocket upgrade rejected: \(respStr.prefix(200))")
            throw VolcASRError.handshakeRejected
        }

        Log.info("[VolcASR] WebSocket upgrade complete (HTTP/1.1)")
        return conn
    }

    // MARK: - Send full client request

    private func sendFullClientRequest(conn: NWConnection, language: String?) async throws {
        var audio: [String: Any] = [
            "format": "pcm",
            "rate": 16000,
            "bits": 16,
            "channel": 1,
            "codec": "raw"
        ]
        if let lang = language { audio["language"] = lang }

        let payload: [String: Any] = [
            "user": ["uid": "opentype_macos"],
            "audio": audio,
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": false
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let message = buildMessage(type: .fullClientRequest, flags: 0x00, serialization: .json, payload: jsonData)
        try await nwSendWS(conn: conn, data: message)
    }

    // MARK: - Stream audio

    private func streamAudioAndCollect(conn: NWConnection, pcmData: Data) async throws -> String {
        let totalChunks = (pcmData.count + Self.chunkSize - 1) / Self.chunkSize
        var lastText = ""

        for i in 0..<totalChunks {
            let start = i * Self.chunkSize
            let end   = min(start + Self.chunkSize, pcmData.count)
            let chunk = pcmData[start..<end]
            let isLast = (i == totalChunks - 1)

            let flags: UInt8 = isLast ? 0x02 : 0x00
            let message = buildMessage(type: .audioOnly, flags: flags, serialization: .none, compression: .none, payload: Data(chunk))
            try await nwSendWS(conn: conn, data: message)

            if let resp = try await receiveResponse(conn: conn) {
                if let text = resp.text, !text.isEmpty {
                    lastText = text
                }
                if let code = resp.errorCode {
                    throw VolcASRError.serverError(code: code, message: resp.errorMessage ?? "Unknown")
                }
            }
        }

        return lastText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Receive

    private struct ParsedResponse {
        var text: String?
        var errorCode: Int?
        var errorMessage: String?
        var isFinal: Bool = false
    }

    private func receiveResponse(conn: NWConnection) async throws -> ParsedResponse? {
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.nwReceiveWS(conn: conn)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                throw VolcASRError.timeout
            }
            guard let result = try await group.next() else { throw VolcASRError.timeout }
            group.cancelAll()
            return result
        }
        return parseResponse(data)
    }

    // MARK: - Binary protocol

    private enum MessageType: UInt8 {
        case fullClientRequest  = 0x01
        case audioOnly          = 0x02
        case fullServerResponse = 0x09
        case errorResponse      = 0x0F
    }

    private enum Serialization: UInt8 {
        case none = 0x00
        case json = 0x01
    }

    private enum PayloadCompression: UInt8 {
        case none = 0x00
        case gzip = 0x01
    }

    private func buildMessage(type: MessageType, flags: UInt8, serialization: Serialization, compression: PayloadCompression = .gzip, payload: Data) -> Data {
        let finalPayload: Data
        let actualCompression: PayloadCompression
        if compression == .gzip, let compressed = Gzip.compress(payload) {
            finalPayload = compressed
            actualCompression = .gzip
        } else {
            finalPayload = payload
            actualCompression = .none
        }

        var data = Data(capacity: 4 + 4 + finalPayload.count)
        data.append(0x11)
        data.append((type.rawValue << 4) | (flags & 0x0F))
        data.append((serialization.rawValue << 4) | actualCompression.rawValue)
        data.append(0x00)
        let size = UInt32(finalPayload.count)
        data.append(UInt8((size >> 24) & 0xFF))
        data.append(UInt8((size >> 16) & 0xFF))
        data.append(UInt8((size >> 8) & 0xFF))
        data.append(UInt8(size & 0xFF))
        data.append(finalPayload)
        return data
    }

    private func parseResponse(_ data: Data) -> ParsedResponse? {
        guard data.count >= 4 else { return nil }

        let msgType        = (data[1] >> 4) & 0x0F
        let flags          = data[1] & 0x0F
        let headerSizeWords = Int(data[0] & 0x0F)
        let headerSize     = headerSizeWords * 4

        if msgType == MessageType.errorResponse.rawValue {
            return parseErrorResponse(data, headerSize: headerSize)
        }

        guard msgType == MessageType.fullServerResponse.rawValue else {
            Log.info("[VolcASR] unexpected message type: 0x\(String(msgType, radix: 16))")
            return nil
        }

        var offset = headerSize
        let hasSequence = (flags & 0x01) != 0
        if hasSequence { offset += 4 }

        guard data.count >= offset + 4 else { return nil }
        let payloadSize = Int(readUInt32(data, at: offset))
        offset += 4

        guard data.count >= offset + payloadSize, payloadSize > 0 else {
            return ParsedResponse(isFinal: (flags & 0x02) != 0)
        }

        let isGzip     = (data[2] & 0x0F) == PayloadCompression.gzip.rawValue
        let rawPayload = Data(data[offset..<(offset + payloadSize)])
        let payloadData: Data
        if isGzip, let decompressed = Gzip.decompress(rawPayload) {
            payloadData = decompressed
        } else {
            payloadData = rawPayload
        }
        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return ParsedResponse(isFinal: (flags & 0x02) != 0)
        }

        // Check for inline error code returned via a normal server response frame
        if let code = json["code"] as? Int, code != 0 {
            let msg = json["message"] as? String ?? "Server error \(code)"
            Log.error("[VolcASR] inline error: code=\(code) message=\(msg)")
            return ParsedResponse(errorCode: code, errorMessage: msg)
        }

        let result = json["result"] as? [String: Any]
        let text   = result?["text"] as? String

        return ParsedResponse(text: text, isFinal: (flags & 0x02) != 0)
    }

    private func parseErrorResponse(_ data: Data, headerSize: Int) -> ParsedResponse {
        var offset = headerSize
        guard data.count >= offset + 4 else {
            return ParsedResponse(errorCode: -1, errorMessage: "Unknown error")
        }
        let errorCode = Int(readUInt32(data, at: offset))
        offset += 4

        guard data.count >= offset + 4 else {
            return ParsedResponse(errorCode: errorCode, errorMessage: "Error \(errorCode)")
        }
        let msgSize = Int(readUInt32(data, at: offset))
        offset += 4

        var errorMsg = "Error \(errorCode)"
        if data.count >= offset + msgSize, msgSize > 0 {
            errorMsg = String(data: Data(data[offset..<(offset + msgSize)]), encoding: .utf8) ?? errorMsg
        }
        return ParsedResponse(errorCode: errorCode, errorMessage: errorMsg)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
    }

    // MARK: - NWConnection helpers

    /// Send raw bytes (used for the HTTP/1.1 upgrade request)
    private func nwSend(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume() }
            })
        }
    }

    /// Send a WebSocket binary frame
    private func nwSendWS(conn: NWConnection, data: Data) async throws {
        let meta    = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "ws-binary", metadata: [meta])
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, contentContext: context, isComplete: true,
                      completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume() }
            })
        }
    }

    /// Receive raw bytes (used to read the HTTP 101 response)
    private func nwReceiveRaw(conn: NWConnection, maxBytes: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: maxBytes) { data, _, _, err in
                if let err { cont.resume(throwing: err) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else { cont.resume(throwing: VolcASRError.handshakeRejected) }
            }
        }
    }

    /// Receive one WebSocket message (binary frame)
    private func nwReceiveWS(conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receiveMessage { data, context, _, err in
                if let err { cont.resume(throwing: err) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else { cont.resume(throwing: VolcASRError.timeout) }
            }
        }
    }

    // MARK: - Audio conversion

    private func convertToPCM16k(url: URL) throws -> Data {
        let srcFile  = try AVAudioFile(forReading: url)
        let srcFormat = srcFile.processingFormat

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw VolcASRError.audioConversionFailed
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw VolcASRError.audioConversionFailed
        }

        let ratio          = 16000.0 / srcFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(srcFile.length) * ratio) + 100
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: estimatedFrames) else {
            throw VolcASRError.audioConversionFailed
        }

        var error: NSError?
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

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        let byteCount = Int(outputBuffer.frameLength) * 2
        guard let int16Data = outputBuffer.int16ChannelData else {
            throw VolcASRError.audioConversionFailed
        }
        return Data(bytes: int16Data[0], count: byteCount)
    }

    // MARK: - Language mapping

    private func volcLanguage(from whisperCode: String?) -> String? {
        switch whisperCode {
        case "zh":  return "zh-CN"
        case "en":  return "en-US"
        case "ja":  return "ja-JP"
        case "ko":  return "ko-KR"
        case "yue": return "yue-CN"
        case "de":  return "de-DE"
        case "fr":  return "fr-FR"
        case "es":  return "es-MX"
        case "pt":  return "pt-BR"
        case "ru":  return "ru-RU"
        case "it":  return "it-IT"
        case "nl":  return "nl-NL"
        case "pl":  return "pl-PL"
        case "tr":  return "tr-TR"
        case "vi":  return "vi-VN"
        case "th":  return "th-TH"
        case "ar":  return "ar-SA"
        case "id":  return "id-ID"
        default:    return nil
        }
    }
}

enum VolcASRError: LocalizedError {
    case notConfigured
    case noAudioFile
    case invalidEndpoint
    case audioConversionFailed
    case timeout
    case handshakeRejected
    case serverError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return L("error.volc_not_configured")
        case .noAudioFile:          return L("error.no_audio")
        case .invalidEndpoint:      return L("error.volc_invalid_endpoint")
        case .audioConversionFailed: return L("error.volc_audio_conversion")
        case .timeout:              return L("error.volc_timeout")
        case .handshakeRejected:    return L("error.volc_handshake_rejected")
        case .serverError(let code, let msg): return "ASR Error \(code): \(msg)"
        }
    }
}
