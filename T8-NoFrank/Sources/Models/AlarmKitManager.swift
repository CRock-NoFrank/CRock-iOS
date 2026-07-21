//
//  AlarmKitManager.swift
//  T8-NoFrank
//
//  iOS 26+ AlarmKit 래퍼. UNUserNotificationCenter 기반 burst 방식 대체.
//  AlarmKit은 시스템 Ringtone 채널로 사운드를 출력 → RingerVolumeController로 그 채널의
//  볼륨을 유저 설정값으로 직접 제어해서 시스템 벨소리 볼륨 무관하게 알람 울리게 함.
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI

/// AlarmKit 메타데이터 — Live Activity 등에서 활용 가능하지만 현재는 비어있음.
@available(iOS 26.0, *)
struct CRockAlarmMetadata: AlarmMetadata {
    init() {}
}

@available(iOS 26.0, *)
final class AlarmKitManager {
    static let shared = AlarmKitManager()

    // MARK: - Stable Identifiers
    // 동일 ID 재사용으로 재예약 시 중복 방지.
    private static let mainAlarmID = UUID(uuidString: "C0CC0001-A1A1-B2B2-C3C3-000000000001")!
    private static let backupAlarmID = UUID(uuidString: "C0CC0001-A1A1-B2B2-C3C3-000000000002")!

    static let mainAlarmIDString = mainAlarmID.uuidString
    static let backupAlarmIDString = backupAlarmID.uuidString

    // AlarmKit이 실제로 울리도록 NotiSound28sec.caf 사용. 시스템 Ringtone 볼륨 채널을 쓰는데,
    // RingerVolumeController (private AVSystemController API)로 Ringtone 볼륨을 유저 설정값으로
    // 강제해서 AlarmKit이 유저가 원하는 볼륨으로 울리게 함.
    private static let alarmSoundName = "NotiSound28sec.caf"
    private static let backupDelaySec: TimeInterval = 60
    private static let appGroupID = "group.CRockWidget"
    private static let needsRockBreakKey = "alarmKit_needsRockBreak"
    private static let lastFireTimestampKey = "alarmKit_lastFireTimestamp"

    private var observerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                return state == .authorized
            } catch {
                print("❌ AlarmKit authorization failed: \(error)")
                return false
            }
        @unknown default:
            return false
        }
    }

    var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    // MARK: - Schedule Main (Weekly Recurring)
    /// 메인 알람을 weekly 반복으로 등록. 동일 ID로 덮어쓰기.
    func scheduleMainAlarm(hour: Int, minute: Int, weekdays: Set<Int>) async {
        guard isAuthorized else {
            print("⚠️ AlarmKit not authorized — skipping schedule")
            return
        }
        guard !weekdays.isEmpty else {
            print("⚠️ No weekdays selected — skipping schedule")
            return
        }

        // 기존 메인 알람 취소 후 재등록 (state 깨끗하게)
        try? AlarmManager.shared.cancel(id: Self.mainAlarmID)

        let localeWeekdays = weekdays.compactMap { Self.localeWeekday(from: $0) }
        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(localeWeekdays)
        let schedule = Alarm.Schedule.relative(
            Alarm.Schedule.Relative(time: time, repeats: recurrence)
        )

        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "돌 깨러 가기"),
            textColor: .white,
            systemImageName: "hammer.fill"
        )
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "CRock"),
            stopButton: stopButton
        )
        let attributes = AlarmAttributes<CRockAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertPresentation),
            metadata: CRockAlarmMetadata(),
            tintColor: Color(red: 0.74, green: 0.37, blue: 0.10) // #BE5F1B
        )

        let configuration = AlarmManager.AlarmConfiguration<CRockAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: BreakRockIntent(alarmID: Self.mainAlarmID.uuidString),
            sound: .named(Self.alarmSoundName)
        )

        do {
            _ = try await AlarmManager.shared.schedule(
                id: Self.mainAlarmID,
                configuration: configuration
            )
            print("✅ AlarmKit main alarm scheduled: \(hour):\(minute), weekdays=\(weekdays)")
        } catch {
            print("❌ Failed to schedule AlarmKit main alarm: \(error)")
        }
    }

    // MARK: - Schedule Backup (One-shot 60s later)
    /// 유저가 락스크린 stop을 눌렀지만 돌을 안 깬 경우 대비. 60초 후 1회 fire.
    /// 돌 깨면 cancelBackup으로 취소. 동일 ID 재사용으로 중복 방지.
    func scheduleBackupAlarm() async {
        guard isAuthorized else { return }

        try? AlarmManager.shared.cancel(id: Self.backupAlarmID)

        let fireDate = Date().addingTimeInterval(Self.backupDelaySec)
        let schedule = Alarm.Schedule.fixed(fireDate)

        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: "돌 깨러 가기"),
            textColor: .white,
            systemImageName: "hammer.fill"
        )
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "CRock"),
            stopButton: stopButton
        )
        let attributes = AlarmAttributes<CRockAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertPresentation),
            metadata: CRockAlarmMetadata(),
            tintColor: Color(red: 0.74, green: 0.37, blue: 0.10)
        )

        let configuration = AlarmManager.AlarmConfiguration<CRockAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: BreakRockIntent(alarmID: Self.backupAlarmID.uuidString),
            sound: .named(Self.alarmSoundName)
        )

        do {
            _ = try await AlarmManager.shared.schedule(
                id: Self.backupAlarmID,
                configuration: configuration
            )
            print("⏰ AlarmKit backup alarm scheduled in \(Int(Self.backupDelaySec))s")
        } catch {
            print("❌ Failed to schedule backup alarm: \(error)")
        }
    }

    // MARK: - Cancel
    func cancelMainAlarm() {
        try? AlarmManager.shared.cancel(id: Self.mainAlarmID)
        print("🗑️ AlarmKit main alarm cancelled")
    }

    func cancelBackupAlarm() {
        try? AlarmManager.shared.cancel(id: Self.backupAlarmID)
        print("🗑️ AlarmKit backup alarm cancelled")
    }

    func cancelAllAlarms() {
        cancelMainAlarm()
        cancelBackupAlarm()
    }

    /// 알람 알림 중인 모든 알람 정지. 락스크린 stop 안 거치고 앱 직접 진입한 경우 사용.
    func stopAlertingAlarms() async {
        stopAlertingAlarmsSync()
    }

    /// stopAlertingAlarms의 sync 버전. playAlarmSound처럼 async 컨텍스트가 아닌 곳에서 즉시 호출.
    func stopAlertingAlarmsSync() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms where alarm.state == .alerting {
            try? AlarmManager.shared.stop(id: alarm.id)
        }
    }

    // MARK: - State Detection
    var hasAlertingAlarm: Bool {
        guard let alarms = try? AlarmManager.shared.alarms else { return false }
        return alarms.contains { $0.state == .alerting }
    }

    /// 직전에 알람이 fire 되었는지 (락스크린 stop으로 종료된 직후 상태 포함).
    /// stopIntent가 timestamp를 찍으므로, 30초 이내 timestamp가 있으면 직전 fire로 간주.
    static func wasAlarmRecentlyFired() -> Bool {
        guard let ud = UserDefaults(suiteName: appGroupID),
              let ts = ud.object(forKey: lastFireTimestampKey) as? TimeInterval,
              ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < 30
    }

    static func markAlarmFired() {
        UserDefaults(suiteName: appGroupID)?
            .set(Date().timeIntervalSince1970, forKey: lastFireTimestampKey)
        UserDefaults(suiteName: appGroupID)?
            .set(true, forKey: needsRockBreakKey)
    }

    static func clearAlarmFiredMark() {
        let ud = UserDefaults(suiteName: appGroupID)
        ud?.removeObject(forKey: lastFireTimestampKey)
        ud?.set(false, forKey: needsRockBreakKey)
    }

    static var needsRockBreak: Bool {
        UserDefaults(suiteName: appGroupID)?.bool(forKey: needsRockBreakKey) ?? false
    }

    // MARK: - Observer
    /// alarmUpdates async sequence 구독. alerting 감지 시 needsRockBreak 마킹 + BreakingStone 라우팅.
    /// AlarmKit 사운드는 silence하지 않고 그대로 두며, BackgroundAudioPlayer가 0.2초 간격으로
    /// 볼륨 setter를 갈겨 유저 설정 볼륨 유지를 시도함.
    func startObserving() {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await alarms in AlarmManager.shared.alarmUpdates {
                let hasAlerting = alarms.contains { $0.state == .alerting }
                if hasAlerting {
                    Self.markAlarmFired()
                    await self.handleAlerting()
                }
            }
        }
    }

    func stopObserving() {
        observerTask?.cancel()
        observerTask = nil
    }

    @MainActor
    private func handleAlerting() async {
        // 앱이 살아있고 alarm이 alerting 상태 → 화면 전환 + in-app loud audio 시작
        guard AppRouter.shared.currentScreen != .breakingStone else { return }
        // BackgroundAudioPlayer가 알람 모드 진입을 처리 (시스템 볼륨 오버라이드 포함)
        if !BackgroundAudioPlayer.shared.isAlarmMode {
            BackgroundAudioPlayer.shared.playAlarmSound()
        }
        AppRouter.shared.navigate(.breakingStone)
    }

    // MARK: - Helpers
    /// Calendar.weekday (1=Sun, 2=Mon ...)를 Locale.Weekday로 변환.
    private static func localeWeekday(from calendarWeekday: Int) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
}

#else
// AlarmKit이 import 불가능한 환경 (iOS 26 미만 SDK)에서도 빌드 가능하도록 빈 스텁.
@available(iOS 26.0, *)
final class AlarmKitManager {
    static let shared = AlarmKitManager()
    private init() {}

    static let mainAlarmIDString = ""
    static let backupAlarmIDString = ""

    var isAuthorized: Bool { false }
    var hasAlertingAlarm: Bool { false }

    func requestAuthorization() async -> Bool { false }
    func scheduleMainAlarm(hour: Int, minute: Int, weekdays: Set<Int>) async {}
    func scheduleBackupAlarm() async {}
    func cancelMainAlarm() {}
    func cancelBackupAlarm() {}
    func cancelAllAlarms() {}
    func stopAlertingAlarms() async {}
    func stopAlertingAlarmsSync() {}
    func startObserving() {}
    func stopObserving() {}

    static func wasAlarmRecentlyFired() -> Bool { false }
    static func markAlarmFired() {}
    static func clearAlarmFiredMark() {}
    static var needsRockBreak: Bool { false }
}
#endif
