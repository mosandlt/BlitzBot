import CoreAudio
import Foundation

/// Lightweight enumerator for Core Audio input devices. Used by Settings to
/// populate the microphone picker and by AudioRecorder to resolve a stored UID
/// back to an `AudioDeviceID` at recording start.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioInputDevices {
    /// Returns all currently-connected devices that have at least one input
    /// stream. Excludes virtual output-only aggregates.
    static func list() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInputStreams(id), let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    /// Returns the system default input device's UID, or nil if none.
    static func defaultInputUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr else { return nil }
        return stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
    }

    /// Resolves a stored UID back to a current `AudioDeviceID`. Returns nil if
    /// the device is no longer connected.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        list().first { $0.uid == uid }?.id
    }

    // MARK: - Private helpers

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let buffer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buffer) == noErr else { return false }
        let bufferList = UnsafeMutableAudioBufferListPointer(buffer)
        for buf in bufferList where buf.mNumberChannels > 0 { return true }
        return false
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var cfStr: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr)
        guard status == noErr, let value = cfStr?.takeRetainedValue() else { return nil }
        return value as String
    }
}
