//
//  IOS18AlarmPlatform.swift
//  T8-NoFrank
//
//  iOS 18 이하의 알람 깨우기 방식. burst 노티(UNCalendarNotificationTrigger)로 울린다.
//

import Foundation
import UserNotifications

final class IOS18AlarmPlatform: AlarmPlatform {

    private static let burstCount = 30
    private static let burstIntervalSec: TimeInterval = 2
    private static let burstPrefix = "ALARM_BURST_"
    private static let alarmSoundName = "stone2_1.caf"

    private let scheduler: NotificationScheduling

    init(scheduler: NotificationScheduling = SystemNotificationScheduler()) {
        self.scheduler = scheduler
    }

    func clearStaleAlarms() {
        cancelAlarmBurst()
    }

    func scheduleAlarm(hour: Int, minute: Int, weekdays: Set<Int>) {}

    func handleAlarmFired() {
        sendLocalNotification()
        scheduleAlarmBurst()
    }

    func stopAlerting() {
        cancelAlarmBurst()
    }

    func cancelAll() {
        cancelAlarmBurst()
    }

    var needsTerminationWarning: Bool { true }

    func applyAlarmVolume(target: Float) {}
    func reinforceAlarmVolume(target: Float) {}
    func restoreAlarmVolume() {}
    func loadPersistedAlarmVolume() {}

    private func sendLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "CRock"
        content.body = NSLocalizedString("alarm_notification_body", comment: "돌 깨러가기 🪨")
        content.userInfo = ["targetScreen": "BreakingStone"]
        content.sound = UNNotificationSound(named: .init("NotiSound28sec.caf"))

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "alarmNotification_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        scheduler.add(request)
    }

    func scheduleAlarmBurst() {
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        scheduler.removePending(identifiers: ids)

        for i in 0..<Self.burstCount {
            let content = UNMutableNotificationContent()
            content.title = "CRock"
            content.body = NSLocalizedString("alarm_notification_body", comment: "돌 깨러가기 🪨")
            content.userInfo = ["targetScreen": "BreakingStone"]
            content.sound = UNNotificationSound(named: .init(Self.alarmSoundName))

            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            var components = DateComponents()
            components.second = Int(Double(i) * Self.burstIntervalSec)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: "\(Self.burstPrefix)\(i)",
                content: content,
                trigger: trigger
            )
            scheduler.add(request)
        }
        print("📬 Alarm burst scheduled: \(Self.burstCount) calendar notifications (every \(Int(Self.burstIntervalSec))s)")
    }

    func cancelAlarmBurst() {
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        scheduler.removePending(identifiers: ids)
        scheduler.removeDelivered(identifiers: ids)
        print("🗑️ Alarm burst cancelled (\(ids.count))")
    }
}
