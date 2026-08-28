//
//  IOS26AlarmPlatform.swift
//  T8-NoFrank
//
//  iOS 26 이상의 알람 깨우기 방식. AlarmKit에 위임하고 Ringtone 채널 볼륨을 제어한다.
//

import Foundation

@available(iOS 26.0, *)
final class IOS26AlarmPlatform: AlarmPlatform {

    private static let appGroupID = "group.CRockWidget"
    private static let originalRingerVolumeKey = "originalRingerVolume"

    private var originalRingerVolume: Float = 1.0

    func clearStaleAlarms() {}

    func scheduleAlarm(hour: Int, minute: Int, weekdays: Set<Int>) {
        Task {
            await AlarmKitManager.shared.scheduleMainAlarm(
                hour: hour, minute: minute, weekdays: weekdays
            )
            AlarmKitManager.shared.startObserving()
        }
    }

    func handleAlarmFired() {
        AlarmKitManager.markAlarmFired()
    }

    func applyAlarmVolume(target: Float) {
        if let currentRinger = RingerVolumeController.shared.getVolume(for: .ringtone) {
            originalRingerVolume = currentRinger
            UserDefaults(suiteName: Self.appGroupID)?
                .set(Double(currentRinger), forKey: Self.originalRingerVolumeKey)
            print("💾 Original Ringtone volume: \(Int(currentRinger * 100))%")
        }
        let ok = RingerVolumeController.shared.setVolume(target, for: .ringtone)
        print("📢 Ringtone volume set to \(Int(target * 100))% — success=\(ok)")
    }

    func reinforceAlarmVolume(target: Float) {
        _ = RingerVolumeController.shared.setVolume(target, for: .ringtone)
    }

    func restoreAlarmVolume() {
        _ = RingerVolumeController.shared.setVolume(originalRingerVolume, for: .ringtone)
        print("🔄 Ringtone volume restored to: \(Int(originalRingerVolume * 100))%")
    }

    func loadPersistedAlarmVolume() {
        if let savedRinger = UserDefaults(suiteName: Self.appGroupID)?
            .double(forKey: Self.originalRingerVolumeKey), savedRinger > 0 {
            originalRingerVolume = Float(savedRinger)
        } else if let currentRinger = RingerVolumeController.shared.getVolume(for: .ringtone) {
            originalRingerVolume = currentRinger
        }
    }

    func stopAlerting() {
        Task {
            await AlarmKitManager.shared.stopAlertingAlarms()
        }
        AlarmKitManager.shared.cancelBackupAlarm()
        AlarmKitManager.clearAlarmFiredMark()
    }

    func cancelAll() {
        AlarmKitManager.shared.cancelAllAlarms()
        AlarmKitManager.shared.stopObserving()
        AlarmKitManager.clearAlarmFiredMark()
    }

    var needsTerminationWarning: Bool { false }
}
