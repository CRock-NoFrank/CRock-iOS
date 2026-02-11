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

    private var currentAlarmID: UUID?
    private var isScheduled = false

    private init() {}

    // MARK: - 권한 요청
    func requestAuthorization() async {
        do {
            let status = try await AlarmManager.shared.requestAuthorization()
        } catch {
            print("❌ AlarmKit authorization failed: \(error)")
        }
    }

    // MARK: - 알람 스케줄 (실제 시간 기반)
    func scheduleAlarm(date: Date) async -> Bool {
        // 기존 알람 취소
        cancelAlarm()

        let alarmID = UUID()
        currentAlarmID = alarmID
        isScheduled = false

        do {
            let stopButton = AlarmButton(
                text: "앱 열기",
                textColor: .white,
                systemImageName: "arrow.up.forward.app.fill"
            )

            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(
                    alert: .init(
                        title: LocalizedStringResource(stringLiteral: "CRock"),
                        stopButton: stopButton
                    )
                ),
                metadata: AlarmMetadata(),
                tintColor: .blue
            )

            let schedule = Alarm.Schedule.fixed(date)

            let config = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes,
                stopIntent: StopAlarmIntent(),
                sound: .named("NotiSound28sec.caf")
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: config)
            isScheduled = true
            print("🔔 AlarmKit alarm scheduled for \(date.formatted()) (id: \(alarmID))")
            return true
        } catch {
            print("❌ AlarmKit schedule failed: \(error)")
            currentAlarmID = nil
            return false
        }
    }

    // MARK: - 알람 취소
    func cancelAlarm() {
        guard let alarmID = currentAlarmID, isScheduled else {
            currentAlarmID = nil
            isScheduled = false
            return
        }
        do {
            try AlarmManager.shared.stop(id: alarmID)
            print("🔕 AlarmKit alarm cancelled")
        } catch {
            print("⚠️ AlarmKit cancel (alarm may have already ended): \(error)")
        }
        currentAlarmID = nil
        isScheduled = false
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
            AlarmKitService.shared.cancelAlarm()
        } else {
            NotificationService.cancelAllNotifications()
        }
        #else
        NotificationExtension.cancelAllNotifications()
        #endif
    }
}
