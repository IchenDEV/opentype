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

final class RealtimeAudioConverter {
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

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

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }

        self.outputFormat = outputFormat
        self.converter = converter
    }

    func convertToPCMData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let converted = try convert(buffer)
        guard let data = converted.int16ChannelData else { return Data() }
        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: data[0], count: byteCount)
    }

    func convertToFloatArray(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let converted = try convert(buffer)
        guard let data = converted.floatChannelData else { return [] }
        let count = Int(converted.frameLength)
        return Array(UnsafeBufferPointer(start: data[0], count: count))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
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
}

enum AudioConversionError: LocalizedError {
    case outputBufferCreationFailed
    case conversionFailed
}
