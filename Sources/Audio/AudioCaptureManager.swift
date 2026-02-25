import AVFoundation
import CoreAudio
import AudioToolbox

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var lastRecordingURL: URL?
    private var levelCallback: ((Float) -> Void)?

    private var isRunning = false

    func cleanupLastRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
    }

    @discardableResult
    func start(deviceID: String?, levelUpdate: @escaping (Float) -> Void) -> Bool {
        if isRunning { stop() }
        cleanupLastRecording()
        levelCallback = levelUpdate

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .denied || authStatus == .restricted {
            Log.error("[AudioCapture] microphone permission denied")
            return false
        }

        if let deviceID, let uid = findDevice(id: deviceID) {
            setInputDevice(uid: uid)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_recording_\(UUID().uuidString).wav")
        lastRecordingURL = url

        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            Log.error("[AudioCapture] cannot create audio file: \(error.localizedDescription)")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)

            let level = self.calculateRMS(buffer: buffer)
            self.levelCallback?(level)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            Log.error("[AudioCapture] engine start failed: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        levelCallback = nil
        isRunning = false
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(max(count, 1)))
        // Logarithmic scaling: amplifies quiet sounds, compresses loud ones
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = (db + 50) / 50   // map -50dB..0dB → 0..1
        return max(min(normalized, 1.0), 0.0)
    }

    // MARK: - Device Management

    static func availableMicrophones() -> [(id: String, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)

        return deviceIDs.compactMap { deviceID -> (id: String, name: String)? in
            guard hasInputChannels(deviceID: deviceID) else { return nil }
            let name = deviceName(deviceID: deviceID) ?? "Unknown"
            let uid = deviceUID(deviceID: deviceID) ?? "\(deviceID)"
            return (id: uid, name: name)
        }
    }

    private func findDevice(id: String) -> String? {
        AudioCaptureManager.availableMicrophones().first { $0.id == id }?.id
    }

    private func setInputDevice(uid: String) {
        guard let deviceID = Self.audioDeviceID(forUID: uid) else { return }
        guard let audioUnit = engine.inputNode.audioUnit else { return }
        var id = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        return deviceIDs.first { deviceUID(deviceID: $0) == uid }
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func getStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let cf = value?.takeUnretainedValue() else { return nil }
        return cf as String
    }
}
