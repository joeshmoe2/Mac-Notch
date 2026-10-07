import Foundation
import IOBluetooth
import SwiftUI

/// Shows a pop-up when Bluetooth headphones (including AirPods) connect.
///
/// Uses IOBluetooth connect/disconnect notifications (no polling).
///
/// Battery level is intentionally not shown: IOBluetooth has no public API for
/// a device's battery. AirPods' levels are only exposed through private
/// selectors (e.g. `batteryPercentSingle`) or undocumented system services,
/// which can break or be rejected, so we leave them out.
@MainActor
final class HeadphonesMonitor: NSObject {
    static let shared = HeadphonesMonitor()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// IOBluetooth reports already-connected devices right after registering; ignore those.
    private var startedAt = Date.distantFuture

    func start() {
        guard connectNotification == nil else { return }
        startedAt = .now
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Self.isHeadphones(device) else { return }
        if let address = device.addressString, disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }
        // Skip the burst of "already connected" callbacks at launch.
        guard Date.now.timeIntervalSince(startedAt) > 3, Prefs.popupHeadphones.value else { return }
        let name = device.name ?? "Headphones"
        let isAirPods = name.localizedCaseInsensitiveContains("airpods")
        NotchWindowManager.shared.showPopup(NotchPopup(
            icon: isAirPods ? "airpodspro" : "headphones",
            iconColor: .white,
            title: name,
            detail: "Connected",
            level: nil,
            trailing: nil
        ))
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectNotifications[address] = nil }
    }

    /// Audio-class devices: headphones, headsets, earbuds, speakers with mics.
    private static func isHeadphones(_ device: IOBluetoothDevice) -> Bool {
        let audioMajorClass: BluetoothDeviceClassMajor = 0x04 // kBluetoothDeviceClassMajorAudio
        if device.deviceClassMajor == audioMajorClass { return true }
        return (device.name ?? "").localizedCaseInsensitiveContains("airpods")
    }
}
