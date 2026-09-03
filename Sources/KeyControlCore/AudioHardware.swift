import CoreAudio
import Foundation

struct AudioDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

enum AudioHardware {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func objectIDs(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var property = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.size else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &values) == noErr else { return [] }
        return values
    }

    static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        return status == noErr ? value as String? : nil
    }

    static func defaultOutput() -> AudioDevice? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let id = objectIDs(system, selector: kAudioHardwarePropertyDefaultOutputDevice).first,
              id != kAudioObjectUnknown,
              let uid = string(id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(id: id, uid: uid, name: string(id, selector: kAudioObjectPropertyName) ?? uid)
    }

    static func processObject(pid: pid_t = getpid()) -> AudioObjectID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var qualifier = pid
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) {
            AudioObjectGetPropertyData(
                system,
                &property,
                UInt32(MemoryLayout<pid_t>.size),
                $0,
                &size,
                &value
            )
        }
        return status == noErr && value != kAudioObjectUnknown ? value : nil
    }

    static func hasNativeVolume(_ device: AudioDevice) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var property = address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(element)
            )
            guard AudioObjectHasProperty(device.id, &property) else { continue }
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device.id, &property, &settable) == noErr, settable.boolValue {
                return true
            }
        }
        return false
    }

    static func describe(_ status: OSStatus) -> String {
        let raw = UInt32(bitPattern: status)
        let bytes = [
            UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
            UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff),
        ]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) {
            return "'\(String(bytes: bytes, encoding: .ascii)!)' (\(status))"
        }
        return String(status)
    }
}
