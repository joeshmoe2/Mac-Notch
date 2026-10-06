import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

/// Output volume + default output device via CoreAudio property listeners
/// (no polling).
@Observable
@MainActor
final class AudioDeviceService {
    static let shared = AudioDeviceService()

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioDeviceID = 0
    private(set) var volume: Float = 0
    private(set) var canSetVolume = false

    @ObservationIgnored private var started = false
    @ObservationIgnored private var volumeListenerDevice: AudioDeviceID?
    @ObservationIgnored private var systemListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?

    private init() {}

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AudioDeviceService.shared.reload() }
            }
        }
        systemListener = listener
        var devicesAddr = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(Self.system, &devicesAddr, nil, listener)
        AudioObjectAddPropertyListenerBlock(Self.system, &defaultAddr, nil, listener)
        reload()
    }

    func stop() {
        guard started, let systemListener else { return }
        started = false
        var devicesAddr = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(Self.system, &devicesAddr, nil, systemListener)
        AudioObjectRemovePropertyListenerBlock(Self.system, &defaultAddr, nil, systemListener)
        removeVolumeListener()
    }

    private func reload() {
        devices = Self.outputDevices()
        defaultOutputID = Self.defaultOutputDevice()
        attachVolumeListener(to: defaultOutputID)
        readVolume()
    }

    // MARK: Volume

    private func attachVolumeListener(to device: AudioDeviceID) {
        guard volumeListenerDevice != device else { return }
        removeVolumeListener()
        var addr = Self.volumeAddress
        guard device != 0, AudioObjectHasProperty(device, &addr) else { return }
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AudioDeviceService.shared.readVolume() }
            }
        }
        AudioObjectAddPropertyListenerBlock(device, &addr, nil, listener)
        volumeListener = listener
        volumeListenerDevice = device
    }

    private func removeVolumeListener() {
        if let device = volumeListenerDevice, let volumeListener {
            var addr = Self.volumeAddress
            AudioObjectRemovePropertyListenerBlock(device, &addr, nil, volumeListener)
        }
        volumeListener = nil
        volumeListenerDevice = nil
    }

    private func readVolume() {
        var addr = Self.volumeAddress
        let device = defaultOutputID
        guard device != 0, AudioObjectHasProperty(device, &addr) else {
            canSetVolume = false
            return
        }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            volume = value
        }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(device, &addr, &settable)
        canSetVolume = settable.boolValue
    }

    func setVolume(_ newValue: Float) {
        var addr = Self.volumeAddress
        var value = Float32(min(max(newValue, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        guard defaultOutputID != 0 else { return }
        AudioObjectSetPropertyData(defaultOutputID, &addr, 0, nil, size, &value)
        volume = value
    }

    // MARK: Devices

    func setDefaultOutput(_ id: AudioDeviceID) {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        AudioObjectSetPropertyData(Self.system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        // The listener will reload; update eagerly for the UI.
        defaultOutputID = id
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id)
        return id
    }

    private static func outputDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize)
            guard streamSize > 0 else { return nil }
            return AudioDevice(id: id, name: name(of: id))
        }
    }

    private static func name(of id: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return "Unknown Device" }
        return name.takeRetainedValue() as String
    }
}
