//
//  AlarmKitService.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//

import Foundation

// MARK: - AlarmKit 전용 코드 (iOS 26 SDK에서만 컴파일)
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI

@available(iOS 26.0, *)
final class AlarmKitService {
    static let shared = AlarmKitService()

    private let defaults = UserDefaults(suiteName: "group.CRockWidget")
    private let allAlarmIDsKey = "AlarmKitAllAlarmIDs"

    /// 등록된 모든 알람 ID를 UserDefaults에 배열로 저장 (잔여 알람 방지)
    private var allAlarmIDs: [UUID] {
        get {
            let strings = defaults?.stringArray(forKey: allAlarmIDsKey) ?? []
            return strings.compactMap { UUID(uuidString: $0) }
        }
        set {
            defaults?.set(newValue.map { $0.uuidString }, forKey: allAlarmIDsKey)
        }
    }

    private init() {}

    // MARK: - 권한 요청
    func requestAuthorization() async {
        do {
            _ = try await AlarmManager.shared.requestAuthorization()
        } catch {
            print("❌ AlarmKit authorization failed: \(error)")
        }
    }

    // MARK: - 알람 스케줄 (실제 시간 기반)
    func scheduleAlarm(date: Date) async -> Bool {
        // 기존 알람을 모두 제거한 뒤 새로 등록 (잔여 알람 포함)
        cancelAllAlarms()

        let alarmID = UUID()
        allAlarmIDs = [alarmID]

        do {
            let stopButton = AlarmButton(
                text: "돌 깨러 가기",
                textColor: Color("Orange1"),
                systemImageName: "stop.circle"
            )

            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(
                    alert: .init(
                        title: LocalizedStringResource(stringLiteral: "기상"),
                        stopButton: stopButton
                    )
                ),
                metadata: AlarmMetadata(),
                tintColor: Color("Orange1")
            )

            let schedule = Alarm.Schedule.fixed(date)

            let config = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes,
                stopIntent: StopAlarmIntent(),
                sound: .named("NotiSound28sec.caf")
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: config)
//            print("🔔 AlarmKit alarm scheduled for \(date.formatted()) (id: \(alarmID))")
            return true
        } catch {
            print("❌ AlarmKit schedule failed: \(error)")
            allAlarmIDs = []
            return false
        }
    }

    // MARK: - 모든 알람 취소 (잔여 알람 포함, 시스템에서 스케줄 제거 + 울리는 알람 정지)
    func cancelAllAlarms() {
        let ids = allAlarmIDs
        guard !ids.isEmpty else { return }

        for alarmID in ids {
            // 1. cancel: 시스템에서 스케줄된 알람 제거
            do {
                try AlarmManager.shared.cancel(id: alarmID)
//                print("🗑️ AlarmKit alarm cancelled (id: \(alarmID))")
            } catch {
                print("❌ AlarmKit cancel failed (id: \(alarmID)): \(error)")
            }

            // 2. stop: 현재 울리고 있는 알람 정지
            do {
                try AlarmManager.shared.stop(id: alarmID)
//                print("🔕 AlarmKit alarm stopped (id: \(alarmID))")
            } catch {
                // 울리고 있지 않으면 무시
            }
        }

        allAlarmIDs = []
    }
}
#endif

// MARK: - 브릿지 (항상 컴파일됨)
enum AlarmKitAvailability {
    /// AlarmKit 권한 요청 (가능한 경우)
    static func requestAuthorizationIfAvailable() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                await AlarmKitService.shared.requestAuthorization()
            }
        }
        #endif
    }

    /// AlarmKit 알람 스케줄 (실제 시간 기반)
    static func scheduleAlarmIfAvailable(date: Date) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                let result = await AlarmKitService.shared.scheduleAlarm(date: date)
                if !result {
                    print("⚠️ AlarmKit schedule failed, will fall back to notification at alarm time")
                }
            }
        }
        #endif
    }

    /// AlarmKit 알람 취소 (가능한 경우)
    static func cancelAlarmIfAvailable() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            AlarmKitService.shared.cancelAllAlarms()
        } else {
            NotificationService.cancelAllNotifications()
        }
        #else
        NotificationExtension.cancelAllNotifications()
        #endif
    }
}
