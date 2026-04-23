import AVFoundation
import Foundation

extension AVAudioPCMBuffer {
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        copy.frameLength = frameLength

        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard
                let source = floatChannelData,
                let destination = copy.floatChannelData
            else {
                return nil
            }

            let byteCount = Int(frameLength) * MemoryLayout<Float>.size
            for channel in 0..<Int(format.channelCount) {
                memcpy(destination[channel], source[channel], byteCount)
            }
        case .pcmFormatInt16:
            guard
                let source = int16ChannelData,
                let destination = copy.int16ChannelData
            else {
                return nil
            }

            let byteCount = Int(frameLength) * MemoryLayout<Int16>.size
            for channel in 0..<Int(format.channelCount) {
                memcpy(destination[channel], source[channel], byteCount)
            }
        default:
            return nil
        }

        return copy
    }
}

struct StreamingAudioChunk {
    let samples: [Float]

    var sampleCount: Int { samples.count }
    var pcm16Data: Data { RealtimeAudioConverter.pcm16Data(from: samples) }
}

final class RealtimeAudioConverter {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init?(
        inputFormat: AVAudioFormat,
        outputCommonFormat: AVAudioCommonFormat,
        sampleRate: Double = 16_000,
        channels: AVAudioChannelCount = 1,
        interleaved: Bool
    ) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: outputCommonFormat,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        ) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
    }

    func convertToPCMData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let converted = try convertBuffer(buffer)
        guard let data = converted.int16ChannelData else { return Data() }
        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: data[0], count: byteCount)
    }

    func convertToFloatArray(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let converted = try convertBuffer(buffer)
        guard let data = converted.floatChannelData else { return [] }
        let count = Int(converted.frameLength)
        return Array(UnsafeBufferPointer(start: data[0], count: count))
    }

    func convertBuffer(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioConversionError.converterCreationFailed
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AudioConversionError.outputBufferCreationFailed
        }

        var sourceBuffer: AVAudioPCMBuffer? = buffer
        var conversionError: NSError?

        _ = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard let currentBuffer = sourceBuffer else {
                outStatus.pointee = .endOfStream
                return nil
            }

            outStatus.pointee = .haveData
            sourceBuffer = nil
            return currentBuffer
        }

        if let conversionError {
            throw conversionError
        }
        return outputBuffer
    }

    static func pcm16Data(from samples: [Float]) -> Data {
        guard !samples.isEmpty else { return Data() }

        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var value = Int16((clamped * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

final class StreamingAudioNormalizer {
    private let floatConverter: RealtimeAudioConverter

    init?(inputFormat: AVAudioFormat) {
        guard let floatConverter = RealtimeAudioConverter(
            inputFormat: inputFormat,
            outputCommonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            return nil
        }

        self.floatConverter = floatConverter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> StreamingAudioChunk {
        let converted = try floatConverter.convertBuffer(buffer)
        guard let data = converted.floatChannelData else {
            return StreamingAudioChunk(samples: [])
        }

        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data[0], count: count))
        return StreamingAudioChunk(samples: samples)
    }
}

enum AudioConversionError: LocalizedError {
    case converterCreationFailed
    case outputBufferCreationFailed
    case conversionFailed
}
