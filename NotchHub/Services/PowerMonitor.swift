import Foundation
import IOKit.ps
import SwiftUI

/// Shows a pop-up when the charger is connected or disconnected.
///
/// Uses `IOPSNotificationCreateRunLoopSource`, which IOKit fires whenever any
/// power source changes, so nothing is polled. We only react when the power
/// source switches between AC and battery (not on every 1% change).
@MainActor
final class PowerMonitor {
    static let shared = PowerMonitor()

    struct Snapshot: Equatable {
        var onAC: Bool
        var isCharging: Bool
        var percent: Int?
        var hasBattery: Bool
    }

    private var source: CFRunLoopSource?
    private var last: Snapshot?

    private init() {}

    func start() {
        guard source == nil else { return }
        last = Self.read()
        let callback: IOPowerSourceCallbackType = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PowerMonitor.shared.powerSourcesChanged() }
            }
        }
        guard let unmanaged = IOPSNotificationCreateRunLoopSource(callback, nil) else { return }
        let source = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    private func powerSourcesChanged() {
        let now = Self.read()
        defer { last = now }
        guard let last, now.hasBattery, now.onAC != last.onAC, Prefs.popupCharger.value else { return }
        let percentText = now.percent.map { "\($0)%" }
        let level = now.percent.map { Double($0) / 100 }
        let popup: NotchPopup
        if now.onAC {
            popup = NotchPopup(icon: "bolt.fill", iconColor: .green,
                               title: now.isCharging ? "Charging" : "Connected to power",
                               detail: now.isCharging ? nil : "Not charging",
                               level: level, trailing: percentText)
        } else {
            let low = (now.percent ?? 100) <= 20
            popup = NotchPopup(icon: low ? "battery.25" : "battery.100", iconColor: low ? .orange : .white,
                               title: "On battery", detail: nil, level: level, trailing: percentText)
        }
        NotchWindowManager.shared.showPopup(popup)
    }

    /// Reads the internal battery state from IOKit's power source info.
    static func read() -> Snapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return Snapshot(onAC: true, isCharging: false, percent: nil, hasBattery: false)
        }
        let providing = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) ?? kIOPMACPowerKey
        for ps in list {
            guard let description = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let percent: Int? = {
                guard let current, let max, max > 0 else { return nil }
                return Int((Double(current) / Double(max) * 100).rounded())
            }()
            let state = description[kIOPSPowerSourceStateKey] as? String
            return Snapshot(onAC: state == kIOPSACPowerValue,
                            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                            percent: percent, hasBattery: true)
        }
        return Snapshot(onAC: providing == kIOPMACPowerKey, isCharging: false, percent: nil, hasBattery: false)
    }
}
