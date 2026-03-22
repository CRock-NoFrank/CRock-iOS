//
//  BackgroundAudioPlayerIOS26.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//
//  iOS 26+ 전용 BackgroundAudioPlayer 서브클래스

#if canImport(AlarmKit)
import AVFoundation
import Foundation
import UIKit
import UserNotifications

@available(iOS 26.0, *)
final class BackgroundAudioPlayerIOS26: BackgroundAudioPlayer {

    private var hasSwappedToSilent = false

    override init() {
        super.init()
        _ = AlarmCoordinator.shared // 인터럽트 옵저버 등록
        setupAppStateObservers()
    }

    // MARK: - App State Observers (AlarmKit 재예약용)
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 백그라운드 전환 시 AlarmKit을 소리 있는 알람으로 재예약 (앱 종료 대비)
            self?.refreshAlarmSoundMode(isSilent: false)
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 포그라운드 복귀 시 무음 스왑 대기 상태로 초기화
            self?.hasSwappedToSilent = false
        }
    }

    private func refreshAlarmSoundMode(isSilent: Bool) {
        guard let alarmTime = alarmTime, !isAlarmMode else { return }
        AlarmKitAvailability.scheduleAlarmIfAvailable(date: alarmTime, isSilent: isSilent)
        print("🔄 App state changed: Rescheduled AlarmKit (isSilent: \(isSilent))")
    }

    // MARK: - 오디오 인터럽트 후 재생 복원 (전화 등 외부 인터럽트 대응)
    override func resumeAfterInterruption() {
        if isAlarmMode {
            // 알람 중 외부 인터럽트(전화 등) 종료 → 세션 복구 후 소리 재생
            setupAudioSession()
            let savedVolume = Float(UserDefaults(suiteName: "group.CRockWidget")?.double(forKey: "alarmVolume") ?? 1.0)
            setSystemVolume(savedVolume)
            audioPlayer?.volume = savedVolume
            audioPlayer?.play()
            print("🔔 인터럽트 종료 → 알람 재개")
        } else {
            // 무음 재생 중 인터럽트 종료 → 무음으로 복원
            audioPlayer?.play()
            audioPlayer?.volume = 0.0
        }
    }

// MARK: - Play Alarm Sound (AlarmKit 인터럽트 후 세션 재확립)
    override func playAlarmSound() {
        // AlarmKit이 오디오 세션을 인터럽트했을 수 있으므로 먼저 세션을 재확립
        setupAudioSession()
        super.playAlarmSound()
    }

    // MARK: - Check Alarm Time (AlarmKit 2초 전 무음 스왑 추가)
    override func checkAlarmTime() {
        guard let alarmTime = alarmTime else { return }

        if !isAlarmMode {
            scheduleTerminationWarning()
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])
        }

        let now = Date()

        // 알람 2초 전: 앱이 살아있으므로 AlarmKit을 완전 취소 (인터럽트 자체를 없앰)
        // isSilent:true 재예약은 AlarmKit이 세션 인터럽트를 유지해서 앱 오디오를 차단하는 문제가 있음
        if now >= alarmTime.addingTimeInterval(-2.0) && now < alarmTime && !isAlarmMode {
            if !hasSwappedToSilent {
                print("⏳ Alarm almost due: cancelling AlarmKit so app audio can play cleanly.")
                AlarmKitAvailability.cancelAlarmIfAvailable()
                hasSwappedToSilent = true
            }
        }

        if now >= alarmTime && !isAlarmMode {
            let currentWeekday = Calendar.current.component(.weekday, from: now)

            if selectedWeekdays.contains(currentWeekday) {
                playAlarmSound()
            } else {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            }
            hasSwappedToSilent = false
        }
    }

    // MARK: - Update Next Alarm Time (AlarmKit 예약 포함)
    override func updateNextAlarmTime(hour: Int, minute: Int) {
        let calendar = Calendar.current
        let now = Date()

        var nextAlarmDate: Date?

        for dayOffset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let weekday = calendar.component(.weekday, from: checkDate)

            if selectedWeekdays.contains(weekday) {
                var comps = calendar.dateComponents([.year, .month, .day], from: checkDate)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0

                if let candidateDate = calendar.date(from: comps),
                   candidateDate > now {
                    nextAlarmDate = candidateDate
                    break
                }
            }
        }

        self.alarmTime = nextAlarmDate

        // 기본적으로는 소리 있는 알람으로 예약 (앱 종료 시 AlarmKit이 소리 담당)
        if let nextDate = nextAlarmDate {
            AlarmKitAvailability.scheduleAlarmIfAvailable(date: nextDate, isSilent: false)
        }

        print("📅 Next alarm time updated: \(nextAlarmDate?.formatted() ?? "nil")")
    }

    // MARK: - Stop Alarm and Back to Silent
    override func stopAlarmAndBackToSilent() {
        guard isAlarmMode else { return }
        AlarmCoordinator.shared.cancelAlarm()

        stopVolumeRestorationTimer()

        setSystemVolume(originalSystemVolume)
        print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")

        audioPlayer?.volume = 0.0
        isAlarmMode = false

        // AlarmKit이 오디오 세션을 가져갔을 수 있으므로 복원
        AlarmCoordinator.shared.recoverAudioSession()

        print("🔍 stopAlarmAndBackToSilent: Before playSilentSound(), audioPlayer nil? \(audioPlayer == nil), isPlaying: \(audioPlayer?.isPlaying ?? false)")
        playSilentSound()
        print("🔍 stopAlarmAndBackToSilent: After playSilentSound(), audioPlayer nil? \(audioPlayer == nil), isPlaying: \(audioPlayer?.isPlaying ?? false)")

        if let alarmTime = alarmTime {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }

        print("🔇 Alarm stopped, back to silent mode")
    }

    // MARK: - Stop All
    override func stopAll() {
        AlarmCoordinator.shared.cancelAlarm()

        stopVolumeRestorationTimer()

        if isAlarmMode {
            setSystemVolume(originalSystemVolume)
            print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")
        }

        audioPlayer?.stop()
        audioPlayer = nil
        checkTimer?.invalidate()
        checkTimer = nil
        isPlaying = false
        isAlarmMode = false
        alarmTime = nil

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        print("🛑 Background audio player stopped")
    }
}
#endif  // canImport(AlarmKit)
