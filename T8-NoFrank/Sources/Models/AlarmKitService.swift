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
import ActivityKit

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
    func scheduleAlarm(date: Date, isSilent: Bool = false) async -> Bool {
        // 기존 알람을 모두 제거한 뒤 새로 등록 (잔여 알람 포함)
        cancelAllAlarms()

        let alarmID = UUID()
        allAlarmIDs = [alarmID]

        do {
            let appGroupID = "group.CRockWidget"
            let savedVolume = UserDefaults(suiteName: appGroupID)?.double(forKey: "alarmVolume") ?? 1.0
            let targetVolume = Double(savedVolume)

            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = .init(
                    title: LocalizedStringResource(stringLiteral: "기상")
                )
            } else {
                // iOS 26.0: stopButton이 있는 deprecated 이니셜라이저 사용
                alert = .init(
                    title: LocalizedStringResource(stringLiteral: "기상"),
                    stopButton: AlarmButton(
                        text: "돌 깨러 가기",
                        textColor: Color("Orange1"),
                        systemImageName: "stop.circle.fill"
                    )
                )
            }

            let presentation = AlarmPresentation(alert: alert)

            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: AlarmMetadata(),
                tintColor: Color("Orange1")
            )

            let schedule = Alarm.Schedule.fixed(date)

            #if targetEnvironment(simulator)
            let alarmSound: AlertConfiguration.AlertSound = .default
            #else
            // 포그라운드(앱이 살아있음)일 때는 시스템 소리를 무음으로 예약하여 앱의 미디어 소리가 주도권을 잡게 함
            // 백그라운드일 때는 실제 소리를 사용
            let soundName = isSilent ? "Silent1s.caf" : "NotiSound28sec.caf"
            let alarmSound: AlertConfiguration.AlertSound = .named(soundName)
            #endif

            let config = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes,
                stopIntent: StopAlarmIntent(),
                sound: alarmSound
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: config)
            print("🔔 AlarmKit scheduled (isSilent: \(isSilent), sound: \(isSilent ? "Silent1s" : "NotiSound28sec"))")
            return true
        } catch {
            print("❌ AlarmKit schedule failed: \(error)")
            allAlarmIDs = []
            return false
        }
    }

    // MARK: - 현재 울리는 알람의 소리만 정지 (UI 유지 시도)
    func stopCurrentAlarmSound() {
        let ids = allAlarmIDs
        for alarmID in ids {
            do {
                // stop은 현재 울리는 소리를 멈춥니다.
                try AlarmManager.shared.stop(id: alarmID)
                print("🔕 AlarmKit sound stopped via stopCurrentAlarmSound (id: \(alarmID))")
            } catch {
                // 울리고 있지 않으면 무시
            }
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
#endif  // canImport(AlarmKit)

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
        #endif  // canImport(AlarmKit)
    }

    /// AlarmKit 알람 스케줄 (실제 시간 기반)
    static func scheduleAlarmIfAvailable(date: Date, isSilent: Bool = false) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                let result = await AlarmKitService.shared.scheduleAlarm(date: date, isSilent: isSilent)
                if !result {
                    print("⚠️ AlarmKit schedule failed, will fall back to notification at alarm time")
                }
            }
        }
        #endif  // canImport(AlarmKit)
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
        NotificationService.cancelAllNotifications()
        #endif
    }

    /// AlarmKit 알람 소리만 중지 (가능한 경우)
    static func stopCurrentAlarmSoundIfAvailable() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            AlarmKitService.shared.stopCurrentAlarmSound()
        }
        #endif
    }
}


